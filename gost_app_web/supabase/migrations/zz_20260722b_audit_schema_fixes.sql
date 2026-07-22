-- ============================================================
-- AUDIT DE COHERENCE DU SCHEMA — corrections (2026-07-22)
-- ============================================================
-- Suite a l'incident du reglement (fonction + colonne disparues), audit
-- systematique : fonctions appelees mais absentes, colonnes ecrites mais
-- inexistantes. Deux defauts REELS trouves, corriges ici.
--
-- Restent connus mais NON corriges (code mort, a supprimer un jour) :
--   - abandon_ludo_game -> finish_ludo_game (absente)   [Ludo V1, remplace par V2]
--   - create_ludo_room  -> table ludo_rooms (absente)   [Ludo V1]
--   - initiate_freemopay_* -> table freemopay_transactions (archivee K-Pay)
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. raise_admin_alert : TROIS bugs qui la rendaient inutilisable
-- ────────────────────────────────────────────────────────────
-- (a) elle inserait dans admin_alerts.context -> la table a `metadata`,
--     pas `context` => 42703 a chaque appel ;
-- (b) `returning id into v_id` avec v_id bigint alors que admin_alerts.id
--     est un UUID => erreur de type ;
-- (c) admin_alerts.user_id est NOT NULL alors que la fonction n'a aucun
--     parametre user_id => 23502 meme une fois (a) et (b) corriges.
--     Les deux appelants passent en fait l'utilisateur DANS le contexte
--     (jsonb_build_object('user_id', new.user_id, ...)) : on l'en extrait.
--     Et la colonne devient nullable, car les alertes systeme
--     (desequilibre de tresorerie, ecart K-Pay) n'ont aucun utilisateur.
--
-- GRAVITE : cette fonction est le canal d'alerte de la detection de
-- fraude (detect_wallet_anomalies, detect_rapid_wins). Tant qu'elle
-- echouait, AUCUNE alerte n'etait levee : payouts anormaux et gains
-- rapides suspects passaient silencieusement.
--
-- Les appelants utilisent `perform` (retour ignore) : on peut donc
-- corriger le type de retour sans rien casser.

-- Alertes systeme (sans utilisateur concerne) : la contrainte NOT NULL
-- rendait la fonction inutilisable meme apres correction de (a) et (b).
ALTER TABLE public.admin_alerts
  ALTER COLUMN user_id DROP NOT NULL;

DROP FUNCTION IF EXISTS public.raise_admin_alert(text, text, text, text, jsonb);

CREATE FUNCTION public.raise_admin_alert(
  p_type        text,
  p_severity    text,
  p_title       text,
  p_description text,
  p_context     jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_id   uuid;
  v_user uuid;
begin
  -- L'utilisateur concerne voyage dans le contexte (cf. detect_rapid_wins,
  -- detect_wallet_anomalies). Cast tolerant : un contexte malforme ne doit
  -- jamais faire echouer une alerte.
  begin
    v_user := nullif(p_context ->> 'user_id', '')::uuid;
  exception when others then
    v_user := null;
  end;

  insert into public.admin_alerts
    (alert_type, severity, title, description, metadata, user_id)
  values
    (p_type, p_severity, p_title, p_description, p_context, v_user)
  returning id into v_id;

  perform public.log_event(
    case p_severity
      when 'critical' then 'critical'
      when 'high'     then 'error'
      when 'medium'   then 'warn'
      else 'info'
    end,
    'admin_alert', p_title, p_context);

  return v_id;
end;
$function$;

COMMENT ON FUNCTION public.raise_admin_alert(text,text,text,text,jsonb)
IS 'Leve une alerte admin (canal de la detection de fraude). Corrigee le 2026-07-22 : ecrivait dans une colonne "context" inexistante, retournait un bigint la ou l''id est un uuid, et ne renseignait pas user_id (NOT NULL) — elle echouait donc systematiquement.';


-- ────────────────────────────────────────────────────────────
-- 2. app_settings.updated_by
-- ────────────────────────────────────────────────────────────
-- update_app_setting ecrit `updated_by`, colonne absente => 42703, donc
-- toute modification de reglage applicatif echouait. La colonne est une
-- info d'audit legitime (qui a change le reglage) : on la cree.
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS updated_by uuid;

COMMENT ON COLUMN public.app_settings.updated_by
IS 'Auteur de la derniere modification du reglage. Restauree le 2026-07-22.';


-- ────────────────────────────────────────────────────────────
-- 3. coinflip_rooms.updated_at
-- ────────────────────────────────────────────────────────────
-- Trouve via cron.job_run_details : le cron `cf-cleanup` echouait
-- toutes les 10 min DEPUIS LE 15 JUILLET (1008 echecs) sur
--   update coinflip_rooms set status='cancelled', updated_at=now()
--
-- CONSEQUENCE MONETAIRE : coinflip_cleanup_stale_rooms() rembourse
-- l'hote AVANT cet update. L'echec annulant toute la transaction, le
-- remboursement partait a la poubelle avec : les rooms abandonnees
-- n'etaient jamais annulees et les mises restaient bloquees.
-- (Pas de double remboursement possible : rien n'avait jamais ete
-- commite, et treasury_refund_all est idempotente via request_id.)
ALTER TABLE public.coinflip_rooms
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

COMMENT ON COLUMN public.coinflip_rooms.updated_at
IS 'Derniere modification de la room. Restauree le 2026-07-22 : son absence cassait le cron de nettoyage/remboursement coinflip.';
