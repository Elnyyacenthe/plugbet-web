-- ============================================================
-- PLUGBET WHEEL — PHASE 2 : Multiplicateurs 2x / 7x + Free spins
-- ============================================================
-- Roue passe a 50 segments. Nouvelles cases speciales :
--   Segment 48 = "2x" (p = 1/50 = 2%)
--   Segment 49 = "7x" (p = 1/50 = 2%)
--
-- Quand la roue tombe sur 2x ou 7x : PAS de payout direct, mais un
-- free spin est enregistre cote serveur avec :
--   - les mises memorisees
--   - le multiplicateur accumule
-- Le joueur appelle wheel_use_free_spin pour utiliser ce tour gratuit.
-- Si ce free spin retombe sur 2x/7x -> stacking : nouveau free spin
-- avec multiplier accumule.
-- Cap : 3 cascades max (anti-jackpot infini).
-- Expiration : 1 heure (pas de stockpile).
--
-- Idempotent (DROP + CREATE / IF NOT EXISTS).
-- ============================================================

begin;

-- ───────────────────────────────────────────────────────────
-- 1) Update table wheel_spins : segment 0..49 + multiplier + chain
-- ───────────────────────────────────────────────────────────
alter table public.wheel_spins
  drop constraint if exists wheel_spins_segment_check;
alter table public.wheel_spins
  add constraint wheel_spins_segment_check check (segment between 0 and 49);

alter table public.wheel_spins
  drop constraint if exists wheel_spins_winning_tile_check;
-- winning_tile peut maintenant valoir 0 = special (segment 2x/7x sans
-- payout direct, free spin a la place).
alter table public.wheel_spins
  add constraint wheel_spins_winning_tile_check check (winning_tile in (0,1,2,5,10,20,40));

-- Columns Phase 2
alter table public.wheel_spins
  add column if not exists multiplier int not null default 1,
  add column if not exists parent_free_spin_id text,
  add column if not exists is_free_spin boolean not null default false;

-- ───────────────────────────────────────────────────────────
-- 2) Table wheel_free_spins : tour gratuit en attente d'utilisation
-- ───────────────────────────────────────────────────────────
create table if not exists public.wheel_free_spins (
  id                   text primary key,                 -- 'fs_<random>'
  user_id              uuid not null references auth.users(id) on delete cascade,
  triggered_by_spin_id text not null references public.wheel_spins(id) on delete cascade,
  multiplier           int not null check (multiplier >= 2),
  bets                 jsonb not null,                   -- mises a rejouer
  cascade_depth        int not null default 1 check (cascade_depth between 1 and 3),
  used                 boolean not null default false,
  expires_at           timestamptz not null default (now() + interval '1 hour'),
  created_at           timestamptz not null default now()
);
create index if not exists idx_wheel_fs_user_unused
  on public.wheel_free_spins(user_id, used, expires_at);

alter table public.wheel_free_spins enable row level security;
drop policy if exists wheel_fs_select on public.wheel_free_spins;
create policy wheel_fs_select on public.wheel_free_spins
  for select using (user_id = auth.uid());

-- ───────────────────────────────────────────────────────────
-- 3) Helper interne : execute le RNG + map vers tuile
-- ───────────────────────────────────────────────────────────
create or replace function public._wheel_rng_segment()
returns int
language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare
  v_rand bytea;
  v_val  int;
begin
  -- Rejection sampling sur 50 segments. 250 = 5*50.
  loop
    v_rand := extensions.gen_random_bytes(1);
    v_val  := get_byte(v_rand, 0);
    exit when v_val < 250;
  end loop;
  return v_val % 50;
end $function$;
revoke all on function public._wheel_rng_segment() from public, anon, authenticated;

-- Map segment -> tile value. 0 = special (2x/7x sans payout direct).
create or replace function public._wheel_segment_to_tile(p_segment int)
returns int
language plpgsql immutable
as $function$
begin
  -- Distribution sur 50 segments :
  --   0..23   = tile 1  (24, 48%)
  --   24..35  = tile 2  (12, 24%)
  --   36..41  = tile 5  ( 6, 12%)
  --   42..44  = tile 10 ( 3,  6%)
  --   45..46  = tile 20 ( 2,  4%)
  --   47      = tile 40 ( 1,  2%)
  --   48      = "2x"    ( 1,  2%) -> winning_tile = 0, free spin x2
  --   49      = "7x"    ( 1,  2%) -> winning_tile = 0, free spin x7
  if p_segment < 24 then return 1;
  elsif p_segment < 36 then return 2;
  elsif p_segment < 42 then return 5;
  elsif p_segment < 45 then return 10;
  elsif p_segment < 47 then return 20;
  elsif p_segment = 47 then return 40;
  else return 0; -- special
  end if;
end $function$;
revoke all on function public._wheel_segment_to_tile(int) from public, anon;

-- Retourne le multiplicateur du segment special (48=2, 49=7).
create or replace function public._wheel_segment_multiplier(p_segment int)
returns int
language plpgsql immutable
as $function$
begin
  if p_segment = 48 then return 2;
  elsif p_segment = 49 then return 7;
  else return 0;
  end if;
end $function$;
revoke all on function public._wheel_segment_multiplier(int) from public, anon;

-- ───────────────────────────────────────────────────────────
-- 4) Update wheel_spin (Phase 2) : meme signature, gere 50 segments
--     + creation free spin si necessaire
-- ───────────────────────────────────────────────────────────
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
  v_segment      int;
  v_winning_tile int;
  v_total_bet    bigint := 0;
  v_winnings     bigint := 0;
  v_stake_on_win bigint := 0;
  v_keys         text[] := array['1','2','5','10','20','40'];
  v_stake        bigint;
  v_key          text;
  v_spec_mult    int := 0;
  v_free_spin_id text := null;
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
      'multiplier',   v_existing.multiplier,
      'winnings',     v_existing.winnings,
      'total_bet',    v_existing.total_bet,
      'bets',         v_existing.bets,
      'new_balance',  wallet_balance(v_uid),
      'free_spin',    null
    );
  end if;

  -- Validation des mises
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

  -- DEBIT
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

  -- RNG segment 0..49
  v_segment      := _wheel_rng_segment();
  v_winning_tile := _wheel_segment_to_tile(v_segment);
  v_spec_mult    := _wheel_segment_multiplier(v_segment);

  if v_spec_mult > 0 then
    -- Segment special : pas de payout direct, free spin enregistre.
    v_free_spin_id := 'fs_' || gen_random_uuid()::text;
    insert into wheel_free_spins (
      id, user_id, triggered_by_spin_id, multiplier, bets, cascade_depth
    ) values (
      v_free_spin_id, v_uid, p_request_id, v_spec_mult, p_bets, 1
    );
  else
    -- Tuile classique : compute winnings = stake × (tile + 1)
    v_stake_on_win := coalesce((p_bets ->> v_winning_tile::text)::bigint, 0);
    if v_stake_on_win > 0 then
      v_winnings := v_stake_on_win * (v_winning_tile + 1);
    end if;

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
  end if;

  -- Audit
  insert into wheel_spins (
    id, user_id, bets, total_bet, segment, winning_tile, winnings,
    multiplier, is_free_spin
  ) values (
    p_request_id, v_uid, p_bets, v_total_bet, v_segment, v_winning_tile, v_winnings,
    1, false
  );

  return jsonb_build_object(
    'idempotent',   false,
    'segment',      v_segment,
    'winning_tile', v_winning_tile,
    'multiplier',   1,
    'winnings',     v_winnings,
    'total_bet',    v_total_bet,
    'bets',         p_bets,
    'new_balance',  wallet_balance(v_uid),
    'free_spin',    case when v_free_spin_id is not null
                         then jsonb_build_object(
                           'id', v_free_spin_id,
                           'multiplier', v_spec_mult,
                           'bets', p_bets
                         )
                         else null end
  );
end $function$;

-- ───────────────────────────────────────────────────────────
-- 5) wheel_use_free_spin : execute un tour gratuit
-- ───────────────────────────────────────────────────────────
-- p_free_spin_id : id retourne par wheel_spin (ou le precedent free spin)
-- p_request_id : idempotence sur ce tour gratuit (nouveau wheel_spins row)
-- ============================================================
create or replace function public.wheel_use_free_spin(
  p_free_spin_id text,
  p_request_id   text
) returns jsonb
 language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare
  v_uid          uuid := auth.uid();
  v_fs           wheel_free_spins;
  v_existing     wheel_spins;
  v_segment      int;
  v_winning_tile int;
  v_winnings     bigint := 0;
  v_stake_on_win bigint := 0;
  v_spec_mult    int := 0;
  v_new_fs_id    text := null;
  v_total_bet    bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTH' using errcode = '42501'; end if;
  if p_request_id is null or length(p_request_id) < 8 then
    raise exception 'MISSING_REQUEST_ID' using errcode = '22023';
  end if;

  -- Idempotence
  select * into v_existing from wheel_spins
    where id = p_request_id and user_id = v_uid;
  if found then
    return jsonb_build_object(
      'idempotent', true,
      'segment',      v_existing.segment,
      'winning_tile', v_existing.winning_tile,
      'multiplier',   v_existing.multiplier,
      'winnings',     v_existing.winnings,
      'total_bet',    v_existing.total_bet,
      'bets',         v_existing.bets,
      'new_balance',  wallet_balance(v_uid),
      'free_spin',    null
    );
  end if;

  -- Recupere et verrouille le free spin
  select * into v_fs from wheel_free_spins
    where id = p_free_spin_id and user_id = v_uid
    for update;
  if not found then
    raise exception 'FREE_SPIN_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_fs.used then
    raise exception 'FREE_SPIN_ALREADY_USED' using errcode = 'P0001';
  end if;
  if v_fs.expires_at < now() then
    raise exception 'FREE_SPIN_EXPIRED' using errcode = 'P0001';
  end if;

  -- Total bet "virtuel" = somme des bets memorisees (pour audit, pas debite)
  v_total_bet := coalesce(
    (select sum((value)::bigint) from jsonb_each_text(v_fs.bets)), 0
  );

  -- Mark used
  update wheel_free_spins set used = true where id = v_fs.id;

  -- RNG
  v_segment      := _wheel_rng_segment();
  v_winning_tile := _wheel_segment_to_tile(v_segment);
  v_spec_mult    := _wheel_segment_multiplier(v_segment);

  if v_spec_mult > 0 then
    -- Cascade : stacking du multiplier si on n'a pas atteint le cap (3)
    if v_fs.cascade_depth < 3 then
      v_new_fs_id := 'fs_' || gen_random_uuid()::text;
      insert into wheel_free_spins (
        id, user_id, triggered_by_spin_id, multiplier, bets, cascade_depth
      ) values (
        v_new_fs_id, v_uid, p_request_id, v_fs.multiplier * v_spec_mult,
        v_fs.bets, v_fs.cascade_depth + 1
      );
    end if;
    -- Pas de payout sur ce free spin si on tombe sur special
  else
    -- Tuile classique : winnings = stake × (tile + 1) × accumulated_multiplier
    v_stake_on_win := coalesce((v_fs.bets ->> v_winning_tile::text)::bigint, 0);
    if v_stake_on_win > 0 then
      v_winnings := v_stake_on_win * (v_winning_tile + 1) * v_fs.multiplier;
    end if;

    if v_winnings > 0 then
      perform _ledger_post(
        v_uid, v_winnings, 'win',
        'wheel_fs_payout:' || p_request_id,
        'wheel', p_request_id,
        jsonb_build_object(
          'source','wheel_free_spin_win', 'request_id', p_request_id,
          'segment', v_segment, 'winning_tile', v_winning_tile,
          'stake_on_winning_tile', v_stake_on_win,
          'multiplier', v_fs.multiplier,
          'free_spin_id', v_fs.id
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
  end if;

  -- Audit (is_free_spin = true, parent_free_spin_id renseigne)
  insert into wheel_spins (
    id, user_id, bets, total_bet, segment, winning_tile, winnings,
    multiplier, parent_free_spin_id, is_free_spin
  ) values (
    p_request_id, v_uid, v_fs.bets, v_total_bet, v_segment, v_winning_tile, v_winnings,
    v_fs.multiplier, v_fs.id, true
  );

  return jsonb_build_object(
    'idempotent',   false,
    'segment',      v_segment,
    'winning_tile', v_winning_tile,
    'multiplier',   v_fs.multiplier,
    'winnings',     v_winnings,
    'total_bet',    v_total_bet,
    'bets',         v_fs.bets,
    'new_balance',  wallet_balance(v_uid),
    'free_spin',    case when v_new_fs_id is not null
                         then jsonb_build_object(
                           'id', v_new_fs_id,
                           'multiplier', v_fs.multiplier * v_spec_mult,
                           'bets', v_fs.bets,
                           'cascade_depth', v_fs.cascade_depth + 1
                         )
                         else null end
  );
end $function$;

-- Grants
revoke all on function public.wheel_use_free_spin(text, text) from public, anon;
grant execute on function public.wheel_use_free_spin(text, text) to authenticated;

-- ───────────────────────────────────────────────────────────
-- 6) Purge cron : expire les free spins non utilises > 1h
-- ───────────────────────────────────────────────────────────
create or replace function public.wheel_free_spins_purge()
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  with d as (
    delete from wheel_free_spins
     where used = true or expires_at < now() - interval '1 day'
    returning 1
  ) select count(*) into v_n from d;
  return v_n;
end $$;
revoke all on function public.wheel_free_spins_purge() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('wheel_free_spins_purge')
      where exists (select 1 from cron.job where jobname = 'wheel_free_spins_purge');
    perform cron.schedule('wheel_free_spins_purge', '30 3 * * *',
      $cron$ select public.wheel_free_spins_purge(); $cron$);
  end if;
end $$;

commit;

-- ============================================================
-- VERIFICATION
-- ============================================================
-- 1. wheel_use_free_spin existe :
--    select proname from pg_proc p
--    join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname like 'wheel%';
-- 2. Test spin classique :
--    perform set_config('request.jwt.claims',
--      jsonb_build_object('sub','TON_UID','role','authenticated')::text, true);
--    select public.wheel_spin(
--      jsonb_build_object('1',100,'5',200),
--      'spin-' || gen_random_uuid()::text);
--    -- Si segment in (48,49) : free_spin sera populated dans la reponse.
-- 3. Force un free spin : insere manuellement et utilise wheel_use_free_spin.
