-- ============================================================
-- AVIATOR - Multiplayer shared bets + cashouts (live feed)
-- ============================================================
-- Run this in Supabase SQL editor.
-- Idempotent : safe to re-run.

-- 1) Shared bets table (visible a tous, broadcast via realtime)
create table if not exists public.aviator_bets (
  id uuid primary key default gen_random_uuid(),
  round_num bigint not null,
  user_id uuid references auth.users(id) on delete cascade,
  username text not null,
  slot smallint not null check (slot in (1, 2)),
  amount int not null check (amount > 0),
  cashed_out_at numeric(10, 2), -- multiplicateur de cashout (null = pas encore cashout)
  win_amount int,               -- gain final (null tant que round pas fini)
  placed_at timestamptz default now(),
  unique (round_num, user_id, slot)
);

create index if not exists idx_aviator_bets_round on public.aviator_bets(round_num);
create index if not exists idx_aviator_bets_recent on public.aviator_bets(placed_at desc);

-- 2) Enable RLS + policies
alter table public.aviator_bets enable row level security;

drop policy if exists "anyone_reads_aviator_bets" on public.aviator_bets;
create policy "anyone_reads_aviator_bets"
  on public.aviator_bets for select
  using (true);

drop policy if exists "user_inserts_own_aviator_bets" on public.aviator_bets;
create policy "user_inserts_own_aviator_bets"
  on public.aviator_bets for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_updates_own_aviator_bets" on public.aviator_bets;
create policy "user_updates_own_aviator_bets"
  on public.aviator_bets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 3) Enable realtime
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'aviator_bets'
  ) then
    execute 'alter publication supabase_realtime add table public.aviator_bets';
  end if;
end $$;

-- 3.5) Fonction server-side : calcule le crash point d'un round
-- Port de _hashRoundNum + generateCrashPoint du Dart (aviator_service.dart)
-- Deterministe : identique pour un round_num donne, sur le serveur comme sur le client.
-- NOTE: la formule est publique (round_num = epoch / 30s) donc un joueur peut
-- theoriquement calculer le crash en avance. Pour vrai casino -> Phase 2 avec
-- server_seed prive + commitment.
create or replace function public._aviator_crash_point(p_round_num bigint)
returns numeric
language plpgsql
immutable
as $$
declare
  v_round_str text := p_round_num::text;
  v_h bigint;
  v_c int;
  v_server_seed text;
  v_combined text;
  v_ratio numeric;
  v_raw numeric;
  i int;
begin
  -- Hash DJB2-like du roundNum
  v_h := 5381;
  for i in 1..length(v_round_str) loop
    v_c := ascii(substr(v_round_str, i, 1));
    v_h := ((v_h << 5) + v_h) # v_c;
    v_h := v_h & 2147483647;
  end loop;
  -- Avalanche XorShift (2 passes) - decorrele roundNums consecutifs.
  v_h := v_h # ((v_h << 13) & 2147483647);
  v_h := v_h # (v_h >> 17);
  v_h := v_h # ((v_h << 5) & 2147483647);
  v_h := v_h & 2147483647;
  v_h := v_h # ((v_h << 13) & 2147483647);
  v_h := v_h # (v_h >> 17);
  v_h := v_h # ((v_h << 5) & 2147483647);
  v_h := v_h & 2147483647;
  v_server_seed := lpad(to_hex(abs(v_h)), 16, '0');

  -- Hash du combined (serverSeed + ':')
  v_combined := v_server_seed || ':';
  v_h := 5381;
  for i in 1..length(v_combined) loop
    v_c := ascii(substr(v_combined, i, 1));
    v_h := ((v_h << 5) + v_h) # v_c;
    v_h := v_h & 2147483647;
  end loop;
  -- Avalanche final (match le Dart generateCrashPoint)
  v_h := v_h # ((v_h << 13) & 2147483647);
  v_h := v_h # (v_h >> 17);
  v_h := v_h # ((v_h << 5) & 2147483647);
  v_h := v_h & 2147483647;
  v_h := v_h # ((v_h << 13) & 2147483647);
  v_h := v_h # (v_h >> 17);
  v_h := v_h # ((v_h << 5) & 2147483647);
  v_h := v_h & 2147483647;
  v_h := abs(v_h);

  -- Distribution discrete elargie (21 buckets, RTP 90% constant).
  -- MUST match Dart generateCrashPoint().
  v_ratio := v_h::numeric / 2147483647::numeric;

  if v_ratio < 0.0500 then return 0.00;
  elsif v_ratio < 0.0600 then return 0.25;
  elsif v_ratio < 0.0750 then return 0.50;
  elsif v_ratio < 0.0900 then return 0.75;
  elsif v_ratio < 0.1000 then return 0.90;
  elsif v_ratio < 0.1818 then return 1.00;
  elsif v_ratio < 0.2500 then return 1.10;
  elsif v_ratio < 0.3333 then return 1.20;
  elsif v_ratio < 0.4000 then return 1.35;
  elsif v_ratio < 0.4857 then return 1.50;
  elsif v_ratio < 0.5500 then return 1.75;
  elsif v_ratio < 0.6400 then return 2.00;
  elsif v_ratio < 0.7000 then return 2.50;
  elsif v_ratio < 0.7750 then return 3.00;
  elsif v_ratio < 0.8200 then return 4.00;
  elsif v_ratio < 0.8714 then return 5.00;
  elsif v_ratio < 0.9100 then return 7.00;
  elsif v_ratio < 0.9400 then return 10.00;
  elsif v_ratio < 0.9550 then return 15.00;
  elsif v_ratio < 0.9700 then return 20.00;
  else return 30.00;
  end if;
end;
$$;

grant execute on function public._aviator_crash_point(bigint) to authenticated;

-- 4) RPC: place a bet (atomic : deduct coins + insert row)
-- Validation : mise uniquement dans la fenetre countdown (0-10s du round).
create or replace function public.aviator_place_bet(
  p_round_num bigint,
  p_slot smallint,
  p_amount int,
  p_username text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bet_id uuid;
  v_balance int;
  v_now_ms bigint;
  v_round_start_ms bigint;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTH';
  end if;
  if p_amount <= 0 then
    raise exception 'BAD_AMOUNT';
  end if;
  if p_slot not in (1, 2) then
    raise exception 'BAD_SLOT';
  end if;

  -- Validation anti-triche : fenetre de mise = countdown (0-5s du round)
  -- 15000ms = duree totale round (kRoundMs), 5000ms = countdown (kCountdownMs)
  -- ATTENTION: ces constantes doivent matcher _kRoundMs et _kCountdownMs
  -- cote client (aviator_provider.dart).
  v_now_ms := (extract(epoch from now()) * 1000)::bigint;
  v_round_start_ms := p_round_num * 15000;
  if v_now_ms < v_round_start_ms - 2000 then
    raise exception 'ROUND_NOT_STARTED';
  end if;
  if v_now_ms >= v_round_start_ms + 5000 then
    raise exception 'BET_WINDOW_CLOSED';
  end if;

  -- Verrouille la ligne wallet pour eviter double-deduct
  select coins into v_balance
    from public.user_profiles
    where id = v_user_id
    for update;

  if v_balance is null then
    raise exception 'NO_PROFILE';
  end if;
  if v_balance < p_amount then
    raise exception 'INSUFFICIENT_COINS';
  end if;

  update public.user_profiles
    set coins = coins - p_amount,
        updated_at = now()
    where id = v_user_id;

  insert into public.aviator_bets (round_num, user_id, username, slot, amount)
    values (p_round_num, v_user_id, p_username, p_slot, p_amount)
    returning id into v_bet_id;

  return v_bet_id;
exception when unique_violation then
  raise exception 'ALREADY_BET';
end;
$$;

grant execute on function public.aviator_place_bet(bigint, smallint, int, text) to authenticated;

-- 5) RPC: cashout (atomic : set cashed_out_at + add coins)
-- Validation anti-triche :
--   • cashout uniquement pendant la phase vol (10-30s du round, +2s tolerance)
--   • p_mult ne peut pas depasser le crash point reel du round
create or replace function public.aviator_cashout(
  p_round_num bigint,
  p_slot smallint,
  p_mult numeric
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_bet record;
  v_win int;
  v_crash numeric;
  v_now_ms bigint;
  v_round_start_ms bigint;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'NOT_AUTH';
  end if;
  if p_mult <= 0 then
    raise exception 'BAD_MULT';
  end if;

  -- Validation fenetre temporelle : entre 5s et 17s apres debut round
  -- (5s countdown + 10s flying max + 2s tolerance reseau)
  v_now_ms := (extract(epoch from now()) * 1000)::bigint;
  v_round_start_ms := p_round_num * 15000;
  if v_now_ms < v_round_start_ms + 5000 - 500 then
    raise exception 'FLIGHT_NOT_STARTED';
  end if;
  if v_now_ms >= v_round_start_ms + 15000 + 2000 then
    raise exception 'ROUND_ENDED';
  end if;

  -- Validation anti-triche : p_mult <= crashPoint
  -- (tolerance 0.01 pour l'arrondi floating point cote client)
  v_crash := public._aviator_crash_point(p_round_num);
  if p_mult > v_crash + 0.01 then
    raise exception 'MULT_EXCEEDS_CRASH';
  end if;

  -- Lock la mise
  select * into v_bet
    from public.aviator_bets
    where round_num = p_round_num
      and user_id = v_user_id
      and slot = p_slot
    for update;

  if not found then
    raise exception 'BET_NOT_FOUND';
  end if;
  if v_bet.cashed_out_at is not null then
    raise exception 'ALREADY_CASHED_OUT';
  end if;

  v_win := floor(v_bet.amount * p_mult)::int;

  update public.aviator_bets
    set cashed_out_at = p_mult,
        win_amount = v_win
    where id = v_bet.id;

  update public.user_profiles
    set coins = coins + v_win,
        updated_at = now()
    where id = v_user_id;

  return v_win;
end;
$$;

grant execute on function public.aviator_cashout(bigint, smallint, numeric) to authenticated;

-- 6) Settle les mises perdues apres crash (appelee cote client par ceux qui ont vu le crash)
-- Utilise si tu veux tracker les pertes dans les stats. Optionnel.
create or replace function public.aviator_settle_loss(
  p_round_num bigint,
  p_slot smallint
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then return; end if;

  update public.aviator_bets
    set win_amount = 0
    where round_num = p_round_num
      and user_id = v_user_id
      and slot = p_slot
      and cashed_out_at is null
      and win_amount is null;
end;
$$;

grant execute on function public.aviator_settle_loss(bigint, smallint) to authenticated;

-- 7) Heure serveur en ms (utilisee par les clients pour corriger leur offset local)
create or replace function public.server_epoch_ms()
returns bigint
language sql
stable
as $$
  select (extract(epoch from now()) * 1000)::bigint;
$$;

grant execute on function public.server_epoch_ms() to anon, authenticated;

-- ============================================================
-- OPTIONNEL : vue agregation pour le panneau "TOTAL BETS"
-- ============================================================
create or replace view public.aviator_current_round_stats as
select
  round_num,
  count(*) as total_bets,
  sum(amount) as total_wagered,
  sum(case when cashed_out_at is not null then win_amount else 0 end) as total_paid,
  count(*) filter (where cashed_out_at is not null) as total_cashed_out
from public.aviator_bets
group by round_num;

grant select on public.aviator_current_round_stats to authenticated;
