-- ============================================================
-- BIG WIN 777 — FIX : remplace wallet_apply_delta par _ledger_post
-- ============================================================
-- Ma migration initiale appelait `wallet_apply_delta` qui n'existe
-- pas dans ce projet (ou avec une autre signature). Le bon nom est
-- `_ledger_post` (c'est ce qu'utilise Penalty + tous les autres jeux).
--
-- Signature reference (cora_v3/01_wallet_ledger.sql) :
--   _ledger_post(
--     p_user_id    uuid,
--     p_amount     bigint,
--     p_type       text,
--     p_request_id text,            -- cle idempotence dans wallet_ledger
--     p_game_type  text default null,
--     p_game_id    text default null,
--     p_metadata   jsonb default '{}'::jsonb
--   )
--
-- Idempotent : CREATE OR REPLACE sur la fonction.
-- ============================================================

begin;

create or replace function public.slots_spin(
  p_bet         bigint,
  p_request_id  text
) returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_uid          uuid := auth.uid();
  v_balance      bigint;
  v_existing     slot_spins;
  v_reels        text[] := array[]::text[];
  v_symbols      text[] := array['cherry','lemon','orange','grape','bell','bar','seven','blank'];
  v_weights      int[]  := array[7,6,5,4,3,3,1,3];   -- somme = 32
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
  if p_bet < 10 or p_bet > 1000 then
    raise exception 'INVALID_BET_RANGE: 10-1000' using errcode = '22023';
  end if;
  if p_request_id is null or length(p_request_id) < 8 then
    raise exception 'MISSING_REQUEST_ID' using errcode = '22023';
  end if;

  -- Idempotence
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

  -- Rate limit
  select max(created_at) into v_last_spin from slot_spins where user_id = v_uid;
  if v_last_spin is not null and (now() - v_last_spin) < interval '800 milliseconds' then
    raise exception 'RATE_LIMIT: trop rapide, patiente' using errcode = 'P0001';
  end if;

  -- Solde (reconcile-friendly)
  begin perform reconcile_user_ledger(v_uid); exception when others then null; end;
  v_balance := wallet_balance(v_uid);
  if v_balance < p_bet then
    raise exception 'INSUFFICIENT_FUNDS: balance=%, bet=%', v_balance, p_bet
      using errcode = 'P0001';
  end if;

  -- ── DEBIT via _ledger_post (V2 wallet_ledger) ──
  perform _ledger_post(
    v_uid, -p_bet, 'bet',
    'slots_bet:' || p_request_id,
    'slots_777', p_request_id,
    jsonb_build_object('source','slots_777_bet','request_id',p_request_id)
  );

  -- Caisse +bet (optionnel : avalee si table absente)
  begin
    update game_treasury set balance        = balance + p_bet,
                             total_received = total_received + p_bet,
                             updated_at     = now()
     where id = 1;
  exception when undefined_table then null;
  end;

  -- RNG : 3 rouleaux
  for i in 1..3 loop
    loop
      v_rand := extensions.gen_random_bytes(1);
      v_val  := get_byte(v_rand, 0);
      exit when v_val < 224;
    end loop;
    v_val := v_val % v_total;

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

  -- Paytable
  if v_reels[1] = v_reels[2] and v_reels[2] = v_reels[3] and v_reels[1] <> 'blank' then
    v_multiplier := coalesce((v_pay3 ->> v_reels[1])::int, 0);
  else
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

  -- ── CREDIT via _ledger_post si gain ──
  if v_payout > 0 then
    perform _ledger_post(
      v_uid, v_payout, 'win',
      'slots_payout:' || p_request_id,
      'slots_777', p_request_id,
      jsonb_build_object(
        'source','slots_777_win', 'request_id', p_request_id,
        'reels', v_reels, 'multiplier', v_multiplier
      )
    );
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

revoke all on function public.slots_spin(bigint, text) from public, anon;
grant execute on function public.slots_spin(bigint, text) to authenticated;

commit;

-- ============================================================
-- VERIFICATION (apres execution) :
-- ============================================================
-- Test reel comme un utilisateur :
--   do $$
--   declare v_uid uuid := 'TON_USER_ID'::uuid;
--   declare v_result jsonb;
--   begin
--     perform set_config('request.jwt.claims',
--       jsonb_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
--     v_result := public.slots_spin(10, 'fix-' || gen_random_uuid()::text);
--     raise notice 'RESULT: %', v_result;
--   end $$;
--
-- Attendu : RESULT: {"reels": [...], "multiplier": ..., "payout": ..., ...}
-- ============================================================
