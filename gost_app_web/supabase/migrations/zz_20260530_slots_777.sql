-- ============================================================
-- BIG WIN 777 — Backend (Phase 2 real money via caisse principale)
-- ============================================================
-- 3 rouleaux, 1 ligne centrale. Mises 10/50/100/500/1000 FCFA.
-- RNG crypto serveur (gen_random_bytes + rejection sampling).
-- Idempotence via request_id en PK (claim-first sur INSERT).
-- Wallet : wallet_apply_delta (V2 ledger).
-- Caisse principale : game_treasury id=1 (+bet a chaque spin,
-- -payout sur gain). Meme pattern que Penalty.
--
-- Paytable IDENTIQUE a lib/games/slots_777/models/slot_models.dart
-- (sinon divergence client/serveur).
--
-- RTP cible : ~78% (house edge ~22%). "Un peu plus rude".
-- ============================================================

-- ───────────────────────────────────────────────────────────
-- 1) TABLE
-- ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.slot_spins (
  id          text PRIMARY KEY,                    -- = request_id (idempotence)
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  bet_amount  bigint NOT NULL CHECK (bet_amount IN (10, 50, 100, 500, 1000)),
  reels       text[] NOT NULL,                     -- ['cherry','seven','bar']
  multiplier  int NOT NULL DEFAULT 0,
  payout      bigint NOT NULL DEFAULT 0,
  is_jackpot  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_slot_spins_user_recent
  ON public.slot_spins(user_id, created_at DESC);

-- ───────────────────────────────────────────────────────────
-- 2) RLS
-- ───────────────────────────────────────────────────────────
ALTER TABLE public.slot_spins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS slot_spins_select ON public.slot_spins;
CREATE POLICY slot_spins_select ON public.slot_spins
  FOR SELECT USING (user_id = auth.uid());

-- ───────────────────────────────────────────────────────────
-- 3) RPC slots_spin
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.slots_spin(
  p_bet         bigint,
  p_request_id  text
) RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_uid          uuid := auth.uid();
  v_balance      bigint;
  v_existing     slot_spins;
  v_reels        text[] := ARRAY[]::text[];
  v_symbols      text[] := ARRAY['cherry','lemon','orange','grape','bell','bar','seven','blank'];
  v_weights      int[]  := ARRAY[7,6,5,4,3,3,1,3];   -- somme = 32
  v_total        int    := 32;
  v_pay3         jsonb  := jsonb_build_object(
    'seven',500, 'bar',100, 'bell',50, 'grape',25,
    'orange',15, 'lemon',10, 'cherry',5
  );
  v_pay2         jsonb  := jsonb_build_object(
    'seven',18, 'bar',4, 'bell',2, 'cherry',2
  );
  v_rand         bytea;
  v_val          int;
  v_cum          int;
  v_sym          text;
  v_multiplier   int := 0;
  v_payout       bigint := 0;
  v_last_spin    timestamptz;
  i              int;
  j              int;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  if p_bet not in (10, 50, 100, 500, 1000) then
    raise exception 'INVALID_BET: must be 10/50/100/500/1000' using errcode = '22023';
  end if;
  if p_request_id is null or length(p_request_id) < 8 then
    raise exception 'MISSING_REQUEST_ID' using errcode = '22023';
  end if;

  -- Idempotence : meme request_id -> renvoie le resultat enregistre
  select * into v_existing from slot_spins
    where id = p_request_id and user_id = v_uid;
  if found then
    return jsonb_build_object(
      'idempotent', true,
      'reels',      v_existing.reels,
      'multiplier', v_existing.multiplier,
      'payout',     v_existing.payout,
      'is_jackpot', v_existing.is_jackpot,
      'new_balance', wallet_balance(v_uid)
    );
  end if;

  -- Rate limit simple : 1 spin / 800ms par user (anti-spam)
  select max(created_at) into v_last_spin from slot_spins where user_id = v_uid;
  if v_last_spin is not null and (now() - v_last_spin) < interval '800 milliseconds' then
    raise exception 'RATE_LIMIT: trop rapide, patiente' using errcode = 'P0001';
  end if;

  -- Verifie solde
  begin perform reconcile_user_ledger(v_uid); exception when others then null; end;
  v_balance := wallet_balance(v_uid);
  if v_balance < p_bet then
    raise exception 'INSUFFICIENT_FUNDS: balance=%, bet=%', v_balance, p_bet
      using errcode = 'P0001';
  end if;

  -- Debit
  perform wallet_apply_delta(
    v_uid, -p_bet, 'bet',
    'slots_bet:' || p_request_id,
    'slots_777', p_request_id,
    jsonb_build_object('source','slots_777_bet','request_id',p_request_id)
  );

  -- Caisse principale : +bet
  begin
    update game_treasury set balance        = balance + p_bet,
                             total_received = total_received + p_bet,
                             updated_at     = now()
     where id = 1;
  exception when undefined_table then null;
  end;

  -- RNG : 3 rouleaux independants via rejection sampling unbiased (mod 32).
  -- gen_random_bytes(1) => 0..255. On rejette 224..255 pour avoir 0..223
  -- (7*32-1) qui % 32 donne une distribution uniforme.
  for i in 1..3 loop
    loop
      v_rand := extensions.gen_random_bytes(1);
      v_val  := get_byte(v_rand, 0);
      exit when v_val < 224;
    end loop;
    v_val := v_val % v_total;

    -- Map val -> symbole via poids cumules
    v_cum := 0;
    v_sym := 'blank';
    for j in 1..array_length(v_symbols, 1) loop
      v_cum := v_cum + v_weights[j];
      if v_val < v_cum then
        v_sym := v_symbols[j];
        exit;
      end if;
    end loop;
    v_reels := array_append(v_reels, v_sym);
  end loop;

  -- Evaluation paytable. Priorite : 3-of-a-kind > meilleur 2-of-a-kind.
  if v_reels[1] = v_reels[2] and v_reels[2] = v_reels[3] and v_reels[1] <> 'blank' then
    v_multiplier := coalesce((v_pay3 ->> v_reels[1])::int, 0);
  else
    -- Check les 3 paires possibles (1,2), (1,3), (2,3) ; garde le meilleur
    if v_reels[1] = v_reels[2] and v_reels[1] <> 'blank' then
      v_multiplier := greatest(v_multiplier, coalesce((v_pay2 ->> v_reels[1])::int, 0));
    end if;
    if v_reels[1] = v_reels[3] and v_reels[1] <> 'blank' then
      v_multiplier := greatest(v_multiplier, coalesce((v_pay2 ->> v_reels[1])::int, 0));
    end if;
    if v_reels[2] = v_reels[3] and v_reels[2] <> 'blank' then
      v_multiplier := greatest(v_multiplier, coalesce((v_pay2 ->> v_reels[2])::int, 0));
    end if;
  end if;

  v_payout := p_bet * v_multiplier;

  -- Credit payout
  if v_payout > 0 then
    perform wallet_apply_delta(
      v_uid, v_payout, 'win',
      'slots_payout:' || p_request_id,
      'slots_777', p_request_id,
      jsonb_build_object(
        'source','slots_777_win', 'request_id', p_request_id,
        'reels', v_reels, 'multiplier', v_multiplier
      )
    );
    -- Caisse principale : -payout
    begin
      update game_treasury set balance        = balance - v_payout,
                               total_paid_out = total_paid_out + v_payout,
                               updated_at     = now()
       where id = 1;
    exception when undefined_table then null;
    end;
  end if;

  -- Audit
  insert into slot_spins (id, user_id, bet_amount, reels, multiplier, payout, is_jackpot)
    values (p_request_id, v_uid, p_bet, v_reels, v_multiplier, v_payout, v_multiplier >= 500);

  return jsonb_build_object(
    'idempotent', false,
    'reels',      v_reels,
    'multiplier', v_multiplier,
    'payout',     v_payout,
    'is_jackpot', v_multiplier >= 500,
    'new_balance', wallet_balance(v_uid)
  );
end;
$function$;

REVOKE ALL ON FUNCTION public.slots_spin(bigint, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.slots_spin(bigint, text) TO authenticated;

-- ============================================================
-- VERIFICATIONS
-- ============================================================
-- 1) Fonction existe :
--    select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname='slots_spin';
-- 2) Test (en tant qu'utilisateur connecte) :
--    select public.slots_spin(10, 'test-' || gen_random_uuid()::text);
-- 3) Audit :
--    select reels, multiplier, payout, created_at
--    from slot_spins order by created_at desc limit 10;
-- 4) Caisse principale :
--    select balance, total_received, total_paid_out from game_treasury where id=1;
