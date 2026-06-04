-- ============================================================
-- PLUGBET WHEEL — Backend (server-RNG + caisse principale)
-- ============================================================
-- Roue 48 segments, 6 tuiles (1/2/5/10/20/40). Multi-mise : le joueur
-- depose des FCFA sur chaque tuile, la roue tombe sur UN segment, la
-- mise sur la tuile correspondante paie stake × (tile+1), les autres
-- mises sont perdues.
--
-- Distribution :
--   24× "1" (p=50.0%)   12× "2" (p=25.0%)   6× "5" (p=12.5%)
--   3× "10" (p= 6.3%)    2× "20" (p= 4.2%)   1× "40" (p= 2.1%)
--
-- RTP par tuile :
--   1   : 1.00 (push)         | 10 : 0.69
--   2   : 0.75                | 20 : 0.875
--   5   : 0.75                | 40 : 0.854
--
-- Securite :
--   - Idempotent via request_id (PK wheel_spins.id)
--   - Rate limit 800ms
--   - RNG crypto-secure rejection sampling sur gen_random_bytes
--   - Limites par tuile [25, 5000], total [25, 25000]
--   - _ledger_post pour debit/credit (V2 wallet_ledger)
--   - game_treasury +bet, -payout (caisse principale)
-- ============================================================

-- ───────────────────────────────────────────────────────────
-- 1) TABLE
-- ───────────────────────────────────────────────────────────
create table if not exists public.wheel_spins (
  id           text primary key,                    -- = request_id
  user_id      uuid not null references auth.users(id) on delete cascade,
  bets         jsonb not null,                      -- {"1":100,"5":250,...}
  total_bet    bigint not null check (total_bet between 25 and 25000),
  segment      int not null check (segment between 0 and 47),
  winning_tile int not null check (winning_tile in (1,2,5,10,20,40)),
  winnings     bigint not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists idx_wheel_spins_user_recent
  on public.wheel_spins(user_id, created_at desc);

-- ───────────────────────────────────────────────────────────
-- 2) RLS
-- ───────────────────────────────────────────────────────────
alter table public.wheel_spins enable row level security;
drop policy if exists wheel_spins_select on public.wheel_spins;
create policy wheel_spins_select on public.wheel_spins
  for select using (user_id = auth.uid());

-- ───────────────────────────────────────────────────────────
-- 3) RPC wheel_spin
-- ───────────────────────────────────────────────────────────
-- p_bets : jsonb {"1":100, "2":50, "5":250, "10":0, "20":0, "40":0}
--          Cles non listees = 0. Au moins 1 cle doit avoir stake > 0.
-- p_request_id : idempotence
-- Retour : {idempotent, segment, winning_tile, winnings, new_balance, bets}
-- ============================================================
create or replace function public.wheel_spin(
  p_bets        jsonb,
  p_request_id  text
) returns jsonb
 language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare
  v_uid          uuid := auth.uid();
  v_existing     wheel_spins;
  v_balance      bigint;
  v_last_spin    timestamptz;
  -- Distribution : table de mapping segment 0..47 -> tile value
  -- Construit dynamiquement avec les bonnes proportions.
  v_segment_map  int[];
  v_segment      int;
  v_winning_tile int;
  v_total_bet    bigint := 0;
  v_winnings     bigint := 0;
  v_stake_on_win bigint := 0;
  v_rand         bytea;
  v_val          int;
  v_keys         text[] := array['1','2','5','10','20','40'];
  v_tile_int     int;
  v_stake        bigint;
  v_key          text;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  if p_request_id is null or length(p_request_id) < 8 then
    raise exception 'MISSING_REQUEST_ID' using errcode = '22023';
  end if;
  if p_bets is null or jsonb_typeof(p_bets) <> 'object' then
    raise exception 'INVALID_BETS' using errcode = '22023';
  end if;

  -- Idempotence
  select * into v_existing from wheel_spins
    where id = p_request_id and user_id = v_uid;
  if found then
    return jsonb_build_object(
      'idempotent', true,
      'segment',      v_existing.segment,
      'winning_tile', v_existing.winning_tile,
      'winnings',     v_existing.winnings,
      'total_bet',    v_existing.total_bet,
      'bets',         v_existing.bets,
      'new_balance',  wallet_balance(v_uid)
    );
  end if;

  -- Validation des mises : chaque tuile [0, 5000], total [25, 25000]
  foreach v_key in array v_keys loop
    v_stake := coalesce((p_bets ->> v_key)::bigint, 0);
    if v_stake < 0 then
      raise exception 'NEGATIVE_BET_ON_TILE_%', v_key using errcode = '22023';
    end if;
    if v_stake > 5000 then
      raise exception 'BET_TOO_HIGH_ON_TILE_% (max 5000)', v_key using errcode = '22023';
    end if;
    if v_stake > 0 and v_stake < 25 then
      raise exception 'BET_TOO_LOW_ON_TILE_% (min 25)', v_key using errcode = '22023';
    end if;
    v_total_bet := v_total_bet + v_stake;
  end loop;
  if v_total_bet < 25 then
    raise exception 'TOTAL_BET_TOO_LOW (min 25)' using errcode = '22023';
  end if;
  if v_total_bet > 25000 then
    raise exception 'TOTAL_BET_TOO_HIGH (max 25000)' using errcode = '22023';
  end if;

  -- Rate limit
  select max(created_at) into v_last_spin from wheel_spins where user_id = v_uid;
  if v_last_spin is not null and (now() - v_last_spin) < interval '800 milliseconds' then
    raise exception 'RATE_LIMIT' using errcode = 'P0001';
  end if;

  -- Solde
  begin perform reconcile_user_ledger(v_uid); exception when others then null; end;
  v_balance := wallet_balance(v_uid);
  if v_balance < v_total_bet then
    raise exception 'INSUFFICIENT_FUNDS: balance=%, total_bet=%', v_balance, v_total_bet
      using errcode = 'P0001';
  end if;

  -- DEBIT via _ledger_post
  perform _ledger_post(
    v_uid, -v_total_bet, 'bet',
    'wheel_bet:' || p_request_id,
    'wheel', p_request_id,
    jsonb_build_object('source','wheel_bet','request_id',p_request_id,'bets',p_bets)
  );

  -- Caisse +bet
  begin
    update game_treasury set balance        = balance + v_total_bet,
                             total_received = total_received + v_total_bet,
                             updated_at     = now()
     where id = 1;
  exception when undefined_table then null;
  end;

  -- RNG : 0..47 via rejection sampling (256 mod 48 = 16, on rejette 240..255)
  loop
    v_rand := extensions.gen_random_bytes(1);
    v_val  := get_byte(v_rand, 0);
    exit when v_val < 240;  -- 240 = 5*48, distribution uniforme 0..239 → mod 48 OK
  end loop;
  v_segment := v_val % 48;

  -- Map segment 0..47 -> tile value (distribution 24/12/6/3/2/1)
  -- Segments 0..23   = tile 1   (24)
  -- Segments 24..35  = tile 2   (12)
  -- Segments 36..41  = tile 5   (6)
  -- Segments 42..44  = tile 10  (3)
  -- Segments 45..46  = tile 20  (2)
  -- Segment  47      = tile 40  (1)
  if v_segment < 24 then
    v_winning_tile := 1;
  elsif v_segment < 36 then
    v_winning_tile := 2;
  elsif v_segment < 42 then
    v_winning_tile := 5;
  elsif v_segment < 45 then
    v_winning_tile := 10;
  elsif v_segment < 47 then
    v_winning_tile := 20;
  else
    v_winning_tile := 40;
  end if;

  -- Compute winnings = stake_on_winning_tile × (winning_tile + 1)
  -- Le +1 inclut le retour de la mise (formule betPawa-like).
  v_stake_on_win := coalesce((p_bets ->> v_winning_tile::text)::bigint, 0);
  if v_stake_on_win > 0 then
    v_winnings := v_stake_on_win * (v_winning_tile + 1);
  end if;

  -- CREDIT via _ledger_post si gain
  if v_winnings > 0 then
    perform _ledger_post(
      v_uid, v_winnings, 'win',
      'wheel_payout:' || p_request_id,
      'wheel', p_request_id,
      jsonb_build_object(
        'source','wheel_win', 'request_id', p_request_id,
        'segment', v_segment, 'winning_tile', v_winning_tile,
        'stake_on_winning_tile', v_stake_on_win
      )
    );
    begin
      update game_treasury set balance        = balance - v_winnings,
                               total_paid_out = total_paid_out + v_winnings,
                               updated_at     = now()
       where id = 1;
    exception when undefined_table then null;
    end;
  end if;

  -- Audit
  insert into wheel_spins (id, user_id, bets, total_bet, segment, winning_tile, winnings)
    values (p_request_id, v_uid, p_bets, v_total_bet, v_segment, v_winning_tile, v_winnings);

  return jsonb_build_object(
    'idempotent',   false,
    'segment',      v_segment,
    'winning_tile', v_winning_tile,
    'winnings',     v_winnings,
    'total_bet',    v_total_bet,
    'bets',         p_bets,
    'new_balance',  wallet_balance(v_uid)
  );
end $function$;

revoke all on function public.wheel_spin(jsonb, text) from public, anon;
grant execute on function public.wheel_spin(jsonb, text) to authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
-- 1. Test reel (en tant qu'user) :
--    do $$
--    declare v_uid uuid := 'TON_USER_ID'::uuid;
--    declare v_result jsonb;
--    begin
--      perform set_config('request.jwt.claims',
--        jsonb_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
--      v_result := public.wheel_spin(
--        jsonb_build_object('1',100,'5',200,'20',50),
--        'wheel-test-' || gen_random_uuid()::text);
--      raise notice 'RESULT: %', v_result;
--    end $$;
-- 2. Historique : select * from wheel_spins order by created_at desc limit 10;
