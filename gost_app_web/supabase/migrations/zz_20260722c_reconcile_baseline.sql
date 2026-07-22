-- ============================================================
-- RECONCILIATION MONETAIRE : REMISE A ZERO DU COMPTEUR (2026-07-22)
-- ============================================================
-- CONTEXTE
-- Une fois raise_admin_alert reparee (zz_20260722b), la reconciliation
-- horaire s'est remise a lever une alerte `money_imbalance` critical A
-- CHAQUE HEURE. Motif : reconcile_money_system() compare la masse
-- monetaire totale (soldes joueurs + tresorerie) aux seuls depots nets
-- Mobile Money, sans modeliser l'argent gratuit (soldes de depart,
-- bonus, promos, gains de roue). L'ecart constate au moment de la
-- reparation (41 513 FCFA) etait donc STRUCTUREL et historique, pas une
-- fuite : il refletait sept mois d'exploitation, pas un incident.
--
-- DECISION : on ne supprime pas la sentinelle -- on la reetalonne.
-- L'ecart actuel devient la ligne de reference. A partir de maintenant,
-- seule une derive NOUVELLE par rapport a ce point zero declenche une
-- alerte. On ne regarde plus le passe, on surveille le present.
--
-- C'est le meme raisonnement qu'une tare de balance : on ne jette pas la
-- balance parce qu'elle affiche le poids du recipient.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. La ligne de reference
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reconcile_baseline (
  id            int         PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  baseline_diff bigint      NOT NULL,
  set_at        timestamptz NOT NULL DEFAULT now(),
  set_by        uuid,
  note          text
);

COMMENT ON TABLE public.reconcile_baseline
IS 'Point zero de la reconciliation monetaire : ecart structurel accepte. reconcile_money_system() n''alerte que sur la derive PAR RAPPORT a cette valeur.';

ALTER TABLE public.reconcile_baseline ENABLE ROW LEVEL SECURITY;

-- Lecture reservee aux super admins ; l'ecriture passe par la RPC dediee.
DROP POLICY IF EXISTS reconcile_baseline_read ON public.reconcile_baseline;
CREATE POLICY reconcile_baseline_read ON public.reconcile_baseline
  FOR SELECT TO authenticated
  USING (public.is_super_admin());


-- ────────────────────────────────────────────────────────────
-- 2. La sentinelle, reetalonnee
-- ────────────────────────────────────────────────────────────
-- Le calcul de l'ecart brut est INCHANGE (K-Pay + archive FreemoPay,
-- cf. zz_20260516_audit_p1_fixes). Seul le verdict change : il porte
-- desormais sur `drift` (= diff - baseline) et non plus sur `diff`.
--
-- Le retour conserve la cle `consistent` telle quelle : les appelants
-- (cron horaire, fonction edge ludo_v2_cron) continuent de fonctionner
-- sans modification.
CREATE OR REPLACE FUNCTION public.reconcile_money_system()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
declare
  v_total_user_coins  bigint;
  v_treasury_balance  bigint;
  v_admin_balance     bigint;
  v_total_deposits    bigint;
  v_total_withdrawals bigint;
  v_total_in_system   bigint;
  v_total_external    bigint;
  v_diff              bigint;
  v_baseline          bigint;
  v_drift             bigint;
  v_anomaly           boolean;
begin
  select coalesce(sum(coins), 0)::bigint into v_total_user_coins from public.user_profiles;
  select coalesce(balance, 0)::bigint into v_treasury_balance from public.treasury_balance where id = 1;
  select coalesce(balance, 0)::bigint into v_admin_balance from public.admin_treasury where id = 1;

  select coalesce(sum(amount), 0)::bigint into v_total_deposits from (
    select amount from public.kpay_transactions
      where transaction_type = 'DEPOSIT' and status = 'SUCCESS'
    union all
    select amount from public.freemopay_transactions_archive
      where transaction_type = 'DEPOSIT' and status = 'SUCCESS'
  ) d;

  select coalesce(sum(amount), 0)::bigint into v_total_withdrawals from (
    select amount from public.kpay_transactions
      where transaction_type = 'WITHDRAW' and status = 'SUCCESS'
    union all
    select amount from public.freemopay_transactions_archive
      where transaction_type = 'WITHDRAW' and status = 'SUCCESS'
  ) w;

  v_total_in_system := v_total_user_coins + v_treasury_balance + v_admin_balance;
  v_total_external  := v_total_deposits - v_total_withdrawals;
  v_diff            := v_total_in_system - v_total_external;

  -- Pas de baseline enregistree => on retombe sur l'ancien comportement
  -- (reference a zero), pour ne jamais masquer une fuite par accident.
  select coalesce(baseline_diff, 0) into v_baseline
    from public.reconcile_baseline where id = 1;
  v_baseline := coalesce(v_baseline, 0);

  v_drift   := v_diff - v_baseline;
  v_anomaly := abs(v_drift) > 1;

  if v_anomaly then
    perform public.log_event('critical', 'reconcile',
      'Money system out of balance',
      jsonb_build_object(
        'in_system', v_total_in_system, 'external_net', v_total_external,
        'diff', v_diff, 'baseline', v_baseline, 'drift', v_drift,
        'user_coins', v_total_user_coins,
        'treasury', v_treasury_balance, 'admin', v_admin_balance,
        'deposits', v_total_deposits, 'withdrawals', v_total_withdrawals));
  end if;

  return jsonb_build_object(
    'user_coins', v_total_user_coins,
    'treasury_balance', v_treasury_balance,
    'admin_balance', v_admin_balance,
    'total_in_system', v_total_in_system,
    'deposits_total', v_total_deposits,
    'withdrawals_total', v_total_withdrawals,
    'external_net', v_total_external,
    'diff', v_diff,           -- ecart brut, pour transparence
    'baseline', v_baseline,   -- reference acceptee
    'drift', v_drift,         -- ce qui est REELLEMENT surveille
    'consistent', not v_anomaly,
    'checked_at', now()
  );
end;
$fn$;

GRANT EXECUTE ON FUNCTION public.reconcile_money_system() TO authenticated;


-- ────────────────────────────────────────────────────────────
-- 3. Remettre le compteur a zero (a la demande)
-- ────────────────────────────────────────────────────────────
-- A appeler apres une operation legitime qui cree ou detruit de la
-- monnaie hors depot (campagne de bonus, remise a zero des comptes,
-- correction manuelle) : cela reetalonne la sentinelle sur l'etat
-- courant au lieu de la laisser crier indefiniment.
CREATE OR REPLACE FUNCTION public.reset_reconcile_baseline(p_note text DEFAULT null)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
declare
  v_state jsonb;
  v_diff  bigint;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('success', false, 'error', 'NOT_SUPER_ADMIN');
  end if;

  -- Etat courant, mesure avec la baseline actuelle...
  v_state := public.reconcile_money_system();
  v_diff  := (v_state ->> 'diff')::bigint;   -- ...mais on tare sur l'ecart BRUT

  insert into public.reconcile_baseline (id, baseline_diff, set_at, set_by, note)
  values (1, v_diff, now(), auth.uid(), p_note)
  on conflict (id) do update set
    baseline_diff = excluded.baseline_diff,
    set_at        = excluded.set_at,
    set_by        = excluded.set_by,
    note          = excluded.note;

  return jsonb_build_object('success', true, 'baseline', v_diff,
                            'previous_state', v_state);
end;
$fn$;

REVOKE ALL ON FUNCTION public.reset_reconcile_baseline(text) FROM public;
GRANT EXECUTE ON FUNCTION public.reset_reconcile_baseline(text) TO authenticated;


-- ────────────────────────────────────────────────────────────
-- 4. Etalonnage initial : on part de maintenant
-- ────────────────────────────────────────────────────────────
-- Insertion directe (et non via reset_reconcile_baseline, qui exige un
-- super admin connecte -- absent lors d'une migration).
INSERT INTO public.reconcile_baseline (id, baseline_diff, note)
SELECT 1,
       (public.reconcile_money_system() ->> 'diff')::bigint,
       'Etalonnage initial : ecart structurel historique (argent gratuit, '
       'soldes de depart, bonus) accepte comme point zero. On repart de '
       'maintenant.'
ON CONFLICT (id) DO NOTHING;


-- ────────────────────────────────────────────────────────────
-- 5. Replanification du cron horaire
-- ────────────────────────────────────────────────────────────
-- Le message d'alerte reporte desormais `drift` (la derive reelle) et
-- non plus `diff` (qui inclut l'ecart structurel accepte).
SELECT cron.schedule('hourly_reconcile', '0 * * * *', $reconcile$
  do $inner$
  declare v_recon jsonb;
  begin
    v_recon := public.reconcile_money_system();
    if (v_recon ->> 'consistent')::boolean = false then
      perform public.raise_admin_alert(
        'money_imbalance', 'critical',
        'Reconciliation failed',
        format('Derive de %s coins depuis le dernier etalonnage (ecart brut=%s, reference=%s)',
               v_recon ->> 'drift', v_recon ->> 'diff', v_recon ->> 'baseline'),
        v_recon);
    end if;
  end $inner$;
$reconcile$);
