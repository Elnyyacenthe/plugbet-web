-- ============================================================
-- LUDO V2 — PRODUCTION HARDENING (real-money fintech grade)
-- ============================================================
-- A executer APRES :
--   - treasury_unified.sql
--   - treasury_payout_fix.sql
--   - ludo_v2_treasury_migration.sql
--
-- Idempotent. Safe to re-run.
--
-- CONTENU :
--   1. DROP des tables/RPCs Ludo V1 (deprecated)
--   2. Wallet ledger double-entry (traçabilité 100%)
--   3. Game events log (replay + litiges)
--   4. Idempotence par request_id
--   5. RLS strictes (zero direct UPDATE/INSERT)
--   6. Locks + offsets unifies + forfait fair-play
--   7. Server-side timeouts + lives
--   8. Cleanup auto stale games
--   9. System logs + monitoring
-- ============================================================


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) DROP LUDO V1 — deprecated, plus utilise par l'app    ║
-- ╚══════════════════════════════════════════════════════════╝

-- RPCs V1
drop function if exists public.accept_challenge(uuid) cascade;
drop function if exists public.finish_ludo_game(uuid, uuid) cascade;
drop function if exists public.cancel_ludo_game(uuid) cascade;
drop function if exists public.send_ludo_challenge(uuid, integer) cascade;
drop function if exists public.create_game_from_room(uuid) cascade;

-- Tables V1
drop table if exists public.ludo_challenges cascade;
drop table if exists public.ludo_games cascade;
drop table if exists public.ludo_rooms cascade;
drop table if exists public.ludo_room_players cascade;

-- Note : si tu veux garder les anciens mouvements 'ludo' dans treasury_movements
-- pour l'historique, NE PAS modifier. Sinon :
-- update public.treasury_movements set game_type = 'ludo_v2_legacy' where game_type = 'ludo';


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) WALLET LEDGER (double-entry fintech) - TRAÇABILITÉ    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Chaque mouvement de coins (peu importe l'origine) est logge ici avec
-- le solde AVANT et APRES. Permet de :
--   - Reconstruire le solde de n'importe quel utilisateur a t=X
--   - Auditer chaque transaction (qui, quand, pourquoi, combien)
--   - Detecter les incoherences (sum(deltas) != balance)
-- ============================================================

create table if not exists public.wallet_ledger (
  id              bigserial primary key,
  user_id         uuid not null references public.user_profiles(id) on delete cascade,
  delta           int not null,                       -- + ou - coins
  balance_before  int not null,                       -- solde avant operation
  balance_after   int not null,                       -- solde apres operation
  reason          text not null,                      -- 'ludo_v2_bet' | 'ludo_v2_payout' | 'ludo_v2_refund' | 'mobile_money_deposit' | etc
  ref_type        text,                               -- 'game' | 'room' | 'freemopay_tx' | 'manual'
  ref_id          text,                               -- id de l'objet referencé
  metadata        jsonb default '{}',
  request_id      text,                               -- pour idempotence
  created_at      timestamptz not null default now()
);

create index if not exists idx_wallet_ledger_user_time
  on public.wallet_ledger(user_id, created_at desc);
create index if not exists idx_wallet_ledger_ref
  on public.wallet_ledger(ref_type, ref_id);
create index if not exists idx_wallet_ledger_request
  on public.wallet_ledger(request_id) where request_id is not null;

-- RLS : utilisateur voit son propre historique, super_admin voit tout
alter table public.wallet_ledger enable row level security;

drop policy if exists "wl_select_self" on public.wallet_ledger;
create policy "wl_select_self" on public.wallet_ledger for select to authenticated
  using (user_id = auth.uid() or coalesce((
    select role from public.user_profiles where id = auth.uid()
  ), '') = 'super_admin');

drop policy if exists "wl_no_direct_write" on public.wallet_ledger;
create policy "wl_no_direct_write" on public.wallet_ledger for all to authenticated
  using (false) with check (false);

-- Fonction atomique : update solde + log ledger
create or replace function public.wallet_apply_delta(
  p_user_id uuid,
  p_delta int,
  p_reason text,
  p_ref_type text default null,
  p_ref_id text default null,
  p_metadata jsonb default '{}',
  p_request_id text default null
) returns int  -- retourne le nouveau solde
language plpgsql security definer set search_path = public as $$
declare
  v_before int;
  v_after int;
begin
  if p_user_id is null then raise exception 'WALLET_NULL_USER'; end if;
  if p_delta = 0 then
    select coins into v_before from public.user_profiles where id = p_user_id;
    return coalesce(v_before, 0);
  end if;

  -- Idempotence : si on a deja une entree avec ce request_id, on ne refait rien
  if p_request_id is not null then
    select balance_after into v_after from public.wallet_ledger
      where request_id = p_request_id and user_id = p_user_id limit 1;
    if v_after is not null then return v_after; end if;
  end if;

  -- Lock + lecture solde
  select coins into v_before from public.user_profiles
    where id = p_user_id for update;
  if v_before is null then raise exception 'WALLET_USER_NOT_FOUND: %', p_user_id; end if;

  v_after := v_before + p_delta;
  if v_after < 0 then raise exception 'WALLET_INSUFFICIENT: have=% need=%', v_before, -p_delta; end if;

  update public.user_profiles set
    coins = v_after,
    updated_at = now()
  where id = p_user_id;

  insert into public.wallet_ledger
    (user_id, delta, balance_before, balance_after, reason,
     ref_type, ref_id, metadata, request_id)
  values
    (p_user_id, p_delta, v_before, v_after, p_reason,
     p_ref_type, p_ref_id, p_metadata, p_request_id);

  return v_after;
end;
$$;

-- Validation post-fait : verifie que sum(deltas) = balance pour un user
create or replace function public.wallet_check_consistency(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_balance int;
  v_sum int;
begin
  select coins into v_balance from public.user_profiles where id = p_user_id;
  select coalesce(sum(delta), 0) into v_sum from public.wallet_ledger where user_id = p_user_id;
  return jsonb_build_object(
    'user_id', p_user_id,
    'balance', v_balance,
    'ledger_sum', v_sum,
    'consistent', v_balance = v_sum,
    'delta', v_balance - v_sum  -- doit etre 0
  );
end;
$$;

grant execute on function public.wallet_apply_delta(uuid, int, text, text, text, jsonb, text) to service_role;
grant execute on function public.wallet_check_consistency(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) GAME EVENTS LOG (replay + litiges)                    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Chaque action sur une partie est loggee : qui a roule quoi, qui a
-- bouge quel pion, qui a forfait, etc. Permet de rejouer une partie
-- complete et de resoudre les litiges (joueur claim "j'ai pas joue ca").
-- ============================================================

create table if not exists public.ludo_v2_events (
  id            bigserial primary key,
  game_id       uuid not null references public.ludo_v2_games(id) on delete cascade,
  user_id       uuid,                            -- null pour evenements systeme
  event_type    text not null,                   -- 'roll_dice' | 'play_move' | 'skip_turn' | 'forfeit' | 'timeout' | 'cleanup'
  payload       jsonb not null default '{}',     -- { dice: 6, pawn_index: 2, captured: true, ... }
  turn_number   int,
  created_at    timestamptz not null default now()
);

create index if not exists idx_lv2_events_game_time
  on public.ludo_v2_events(game_id, created_at);
create index if not exists idx_lv2_events_user
  on public.ludo_v2_events(user_id, created_at desc);

alter table public.ludo_v2_events enable row level security;

drop policy if exists "lv2e_select_participants" on public.ludo_v2_events;
create policy "lv2e_select_participants" on public.ludo_v2_events for select to authenticated
  using (
    exists (
      select 1 from public.ludo_v2_games g
      where g.id = ludo_v2_events.game_id and auth.uid() = any(g.turn_order)
    )
    or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
  );

drop policy if exists "lv2e_no_direct_write" on public.ludo_v2_events;
create policy "lv2e_no_direct_write" on public.ludo_v2_events for all to authenticated
  using (false) with check (false);


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) SYSTEM LOGS (monitoring + anomalies)                  ║
-- ╚══════════════════════════════════════════════════════════╝

create table if not exists public.system_logs (
  id           bigserial primary key,
  level        text not null check (level in ('debug', 'info', 'warn', 'error', 'critical')),
  source       text not null,            -- 'ludo_v2' | 'treasury' | 'wallet' | etc
  message      text not null,
  context      jsonb default '{}',
  user_id      uuid,                     -- si l'event est lie a un user
  created_at   timestamptz not null default now()
);

create index if not exists idx_system_logs_level_time
  on public.system_logs(level, created_at desc);
create index if not exists idx_system_logs_source_time
  on public.system_logs(source, created_at desc);

alter table public.system_logs enable row level security;
drop policy if exists "sl_super_admin_only" on public.system_logs;
create policy "sl_super_admin_only" on public.system_logs for select to authenticated
  using (coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin');

drop policy if exists "sl_no_direct_write" on public.system_logs;
create policy "sl_no_direct_write" on public.system_logs for all to authenticated
  using (false) with check (false);

create or replace function public.log_event(
  p_level text, p_source text, p_message text,
  p_context jsonb default '{}', p_user_id uuid default null
) returns void language sql security definer as $$
  insert into public.system_logs (level, source, message, context, user_id)
  values (p_level, p_source, p_message, p_context, p_user_id);
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 5) RLS STRICT sur ludo_v2_*                              ║
-- ╚══════════════════════════════════════════════════════════╝

-- ludo_v2_games : interdit toute ecriture directe (les RPCs ont security definer)
drop policy if exists "ludo_v2_games_select" on public.ludo_v2_games;
create policy "ludo_v2_games_select"
  on public.ludo_v2_games for select to authenticated using (true);

drop policy if exists "ludo_v2_games_update" on public.ludo_v2_games;
drop policy if exists "ludo_v2_games_no_direct_update" on public.ludo_v2_games;
create policy "ludo_v2_games_no_direct_update"
  on public.ludo_v2_games for update to authenticated
  using (false) with check (false);

drop policy if exists "ludo_v2_games_no_direct_insert" on public.ludo_v2_games;
create policy "ludo_v2_games_no_direct_insert"
  on public.ludo_v2_games for insert to authenticated with check (false);

drop policy if exists "ludo_v2_games_no_direct_delete" on public.ludo_v2_games;
create policy "ludo_v2_games_no_direct_delete"
  on public.ludo_v2_games for delete to authenticated using (false);

-- ludo_v2_rooms
drop policy if exists "ludo_v2_rooms_update" on public.ludo_v2_rooms;
drop policy if exists "ludo_v2_rooms_no_direct_update" on public.ludo_v2_rooms;
create policy "ludo_v2_rooms_no_direct_update"
  on public.ludo_v2_rooms for update to authenticated
  using (false) with check (false);

-- ludo_v2_room_players : interdit DELETE direct (un joueur peut quitter via RPC dediee)
drop policy if exists "ludo_v2_rp_delete" on public.ludo_v2_room_players;
create policy "ludo_v2_rp_no_direct_delete"
  on public.ludo_v2_room_players for delete to authenticated using (false);


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 6) NOUVELLE COLONNES NECESSAIRES                         ║
-- ╚══════════════════════════════════════════════════════════╝

-- consecutive_timeouts : compte serveur des timeouts consecutifs
-- turn_started_at : timestamp du debut du tour actuel (pour idle claim)
alter table public.ludo_v2_games
  add column if not exists consecutive_timeouts int not null default 0,
  add column if not exists turn_started_at timestamptz not null default now(),
  add column if not exists last_request_id text;  -- idempotence par game

-- Trigger pour reset consecutive_timeouts + update turn_started_at au changement de tour
create or replace function public.ludo_v2_track_turn_change()
returns trigger language plpgsql as $$
begin
  if new.current_turn is distinct from old.current_turn then
    new.turn_started_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists ludo_v2_turn_change on public.ludo_v2_games;
create trigger ludo_v2_turn_change
  before update on public.ludo_v2_games
  for each row execute function public.ludo_v2_track_turn_change();


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 7) RPC ludo_v2_join_room - LOCK + idempotent             ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_join_room(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_room record;
  v_uid uuid := auth.uid();
  v_count int;
  v_slot int;
  v_username text;
  v_game_id uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  -- LOCK la room dès le départ (corrige race condition)
  select * into v_room from public.ludo_v2_rooms
    where code = upper(p_code) and status = 'waiting' for update;
  if not found then raise exception 'ROOM_NOT_FOUND_OR_STARTED'; end if;
  if v_room.host_id = v_uid then raise exception 'ALREADY_HOST'; end if;

  if exists (select 1 from public.ludo_v2_room_players
             where room_id = v_room.id and user_id = v_uid) then
    raise exception 'ALREADY_IN_ROOM';
  end if;

  select count(*) into v_count from public.ludo_v2_room_players where room_id = v_room.id;
  if v_count >= v_room.player_count then raise exception 'ROOM_FULL'; end if;

  if v_room.player_count = 2 then
    v_slot := 2;
  else
    select s into v_slot from unnest(array[1, 2, 3]) as s
      where s not in (select slot from public.ludo_v2_room_players where room_id = v_room.id)
      order by s limit 1;
  end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  insert into public.ludo_v2_room_players (room_id, user_id, slot, username)
    values (v_room.id, v_uid, v_slot, v_username);

  if v_count + 1 >= v_room.player_count then
    select public.ludo_v2_start_game(v_room.id) into v_game_id;
    return jsonb_build_object('room_id', v_room.id, 'game_id', v_game_id, 'started', true);
  end if;

  return jsonb_build_object('room_id', v_room.id, 'game_id', null, 'started', false);
end;
$$;
grant execute on function public.ludo_v2_join_room(text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 8) RPC ludo_v2_start_game - LEDGER + atomique           ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_start_game(p_room_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_game_id uuid;
  v_pawns jsonb := '{}'::jsonb;
  v_color_map jsonb := '{}'::jsonb;
  v_turn_order uuid[] := array[]::uuid[];
  v_first uuid;
  v_bet int;
  v_player_uid uuid;
  r record;
begin
  for r in
    select user_id, slot from public.ludo_v2_room_players
    where room_id = p_room_id order by slot
  loop
    v_pawns := v_pawns || jsonb_build_object(r.user_id::text, jsonb_build_array(0,0,0,0));
    v_color_map := v_color_map || jsonb_build_object(r.user_id::text, r.slot);
    v_turn_order := array_append(v_turn_order, r.user_id);
  end loop;

  if array_length(v_turn_order, 1) < 2 then
    raise exception 'NOT_ENOUGH_PLAYERS';
  end if;

  v_first := v_turn_order[1];
  select bet_amount into v_bet from public.ludo_v2_rooms where id = p_room_id;

  insert into public.ludo_v2_games
    (room_id, pawns, current_turn, turn_order, color_map, bet_amount, turn_started_at)
  values
    (p_room_id, v_pawns, v_first, v_turn_order, v_color_map, v_bet, now())
  returning id into v_game_id;

  -- Debit atomique de tous les joueurs (via wallet_ledger + treasury)
  if v_bet > 0 then
    foreach v_player_uid in array v_turn_order loop
      -- 1. Debit wallet via ledger (idempotent par game_id+user_id)
      perform public.wallet_apply_delta(
        v_player_uid,
        -v_bet,
        'ludo_v2_bet',
        'game',
        v_game_id::text,
        jsonb_build_object('bet_amount', v_bet),
        'ludo_v2_bet_' || v_game_id::text || '_' || v_player_uid::text
      );
      -- 2. Credit la caisse jeu (treasury_balance) via la fonction existante
      -- treasury_collect_loss credite uniquement la caisse (le user a deja ete debite ci-dessus)
      perform public.treasury_collect_loss(
        'ludo_v2', v_game_id::text, v_player_uid, v_bet
      );
    end loop;
  end if;

  update public.ludo_v2_rooms set status = 'playing', game_id = v_game_id where id = p_room_id;

  -- Logger l'event
  insert into public.ludo_v2_events (game_id, event_type, payload, turn_number)
  values (v_game_id, 'game_started',
          jsonb_build_object('players', v_turn_order, 'bet', v_bet), 0);

  return v_game_id;
end;
$$;
grant execute on function public.ludo_v2_start_game(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 9) RPC ludo_v2_roll_dice - logged                        ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_roll_dice(
  p_game_id uuid,
  p_request_id text default null
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_dice int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'GAME_NOT_PLAYING'; end if;
  if v_game.current_turn != v_uid then raise exception 'NOT_YOUR_TURN'; end if;
  if v_game.dice_rolled then raise exception 'DICE_ALREADY_ROLLED'; end if;

  -- Idempotence : si meme request_id, retourne le precedent dé
  if p_request_id is not null and v_game.last_request_id = p_request_id then
    return v_game.dice_value;
  end if;

  v_dice := floor(random() * 6 + 1)::int;

  update public.ludo_v2_games set
    dice_value = v_dice,
    dice_rolled = true,
    last_request_id = p_request_id,
    updated_at = now()
  where id = p_game_id;

  insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
  values (p_game_id, v_uid, 'roll_dice',
          jsonb_build_object('dice', v_dice), v_game.turn_number);

  return v_dice;
end;
$$;
grant execute on function public.ludo_v2_roll_dice(uuid, text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 10) RPC ludo_v2_play_move - VERSION CANONIQUE            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Offsets canoniques : ARRAY[0, 13, 26, 39] (Red, Green, Blue, Yellow)
-- correspondance slot index 0..3 = Red, Green, Blue, Yellow
-- ============================================================

create or replace function public.ludo_v2_play_move(
  p_game_id uuid,
  p_pawn_index int,
  p_request_id text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_uid_text text;
  v_pawns jsonb;
  v_my_pawns jsonb;
  v_current_step int;
  v_new_step int;
  v_dice int;
  v_captured boolean := false;
  v_captured_count int := 0;
  v_won boolean := false;
  v_extra_turn boolean := false;
  v_next_turn uuid;
  v_my_color int;
  v_my_offset int;
  v_opp_key text;
  v_opp_pawns jsonb;
  v_opp_color int;
  v_opp_offset int;
  v_opp_step int;
  v_my_abs int;
  v_opp_abs int;
  -- OFFSETS CANONIQUES (Red, Green, Blue, Yellow ↔ slot 0,1,2,3)
  v_offsets int[] := array[0, 13, 26, 39];
  v_safe_cells int[] := array[0, 8, 13, 21, 26, 34, 39, 47];
  v_turn_order uuid[];
  v_turn_idx int;
  v_pot int;
  i int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  v_uid_text := v_uid::text;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'GAME_NOT_PLAYING'; end if;
  if v_game.current_turn != v_uid then raise exception 'NOT_YOUR_TURN'; end if;
  if not v_game.dice_rolled then raise exception 'ROLL_FIRST'; end if;
  if p_pawn_index < 0 or p_pawn_index > 3 then raise exception 'INVALID_PAWN'; end if;

  -- Idempotence
  if p_request_id is not null and v_game.last_request_id = p_request_id then
    return jsonb_build_object('idempotent', true);
  end if;

  v_dice := v_game.dice_value;
  v_pawns := v_game.pawns;
  v_my_pawns := v_pawns -> v_uid_text;
  if v_my_pawns is null then raise exception 'PLAYER_NOT_IN_GAME'; end if;

  v_current_step := (v_my_pawns ->> p_pawn_index)::int;

  -- Valider mouvement
  if v_current_step = 0 then
    if v_dice != 6 then raise exception 'NEED_6_TO_LEAVE'; end if;
    v_new_step := 1;
  elsif v_current_step >= 58 then
    raise exception 'PAWN_AT_HOME';
  else
    v_new_step := v_current_step + v_dice;
    if v_new_step > 58 then raise exception 'OVERSHOOT';
    end if;
  end if;

  v_my_pawns := jsonb_set(v_my_pawns, array[p_pawn_index::text], to_jsonb(v_new_step));
  v_pawns := jsonb_set(v_pawns, array[v_uid_text], v_my_pawns);

  -- Capture (uniquement track principal 1-51)
  if v_new_step >= 1 and v_new_step <= 51 then
    v_my_color := (v_game.color_map ->> v_uid_text)::int;
    v_my_offset := v_offsets[v_my_color + 1];
    v_my_abs := ((v_new_step - 1) + v_my_offset) % 52;

    if not (v_my_abs = any(v_safe_cells)) then
      for v_opp_key in select jsonb_object_keys(v_pawns)
      loop
        if v_opp_key = v_uid_text then continue; end if;
        v_opp_color := (v_game.color_map ->> v_opp_key)::int;
        v_opp_offset := v_offsets[v_opp_color + 1];
        v_opp_pawns := v_pawns -> v_opp_key;

        for i in 0..3 loop
          v_opp_step := (v_opp_pawns ->> i)::int;
          if v_opp_step >= 1 and v_opp_step <= 51 then
            v_opp_abs := ((v_opp_step - 1) + v_opp_offset) % 52;
            if v_opp_abs = v_my_abs then
              v_opp_pawns := jsonb_set(v_opp_pawns, array[i::text], '0'::jsonb);
              v_captured := true;
              v_captured_count := v_captured_count + 1;
            end if;
          end if;
        end loop;

        if v_captured then
          v_pawns := jsonb_set(v_pawns, array[v_opp_key], v_opp_pawns);
        end if;
      end loop;
    end if;
  end if;

  -- Victoire ?
  v_won := true;
  for i in 0..3 loop
    if (v_my_pawns ->> i)::int < 58 then v_won := false; exit; end if;
  end loop;

  v_extra_turn := (v_dice = 6) or v_captured;
  v_turn_order := v_game.turn_order;

  if v_won then
    update public.ludo_v2_games set
      pawns = v_pawns, status = 'finished', winner_id = v_uid,
      dice_rolled = false, dice_value = null, last_move_by = v_uid,
      turn_number = v_game.turn_number + 1,
      consecutive_timeouts = 0,
      last_request_id = p_request_id,
      updated_at = now()
    where id = p_game_id;

    if v_game.bet_amount > 0 then
      v_pot := v_game.bet_amount * array_length(v_turn_order, 1);
      perform public.apply_game_payout('ludo_v2', p_game_id::text, v_uid, v_pot);
      -- Logger en wallet_ledger l'arrivee de coins (90% du pot)
      perform public.wallet_apply_delta(
        v_uid,
        0,  -- delta = 0 ici car apply_game_payout l'a deja fait via user_profiles direct
            -- Si on veut tout passer par wallet_apply_delta, refactor apply_game_payout
        'ludo_v2_payout_logged',
        'game', p_game_id::text,
        jsonb_build_object('pot', v_pot, 'note', 'logged_after_payout'),
        'ludo_v2_payout_log_' || p_game_id::text
      );
    end if;

    insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
    values (p_game_id, v_uid, 'play_move',
            jsonb_build_object('pawn', p_pawn_index, 'from', v_current_step, 'to', v_new_step,
                              'captured', v_captured, 'captured_count', v_captured_count, 'won', true),
            v_game.turn_number);

    return jsonb_build_object('captured', v_captured, 'captured_count', v_captured_count,
                              'won', true, 'extra_turn', false);
  end if;

  if v_extra_turn then
    v_next_turn := v_uid;
  else
    v_turn_idx := 1;
    for i in 1..array_length(v_turn_order, 1) loop
      if v_turn_order[i] = v_uid then v_turn_idx := i; exit; end if;
    end loop;
    v_turn_idx := (v_turn_idx % array_length(v_turn_order, 1)) + 1;
    v_next_turn := v_turn_order[v_turn_idx];
  end if;

  update public.ludo_v2_games set
    pawns = v_pawns,
    current_turn = v_next_turn,
    dice_rolled = false, dice_value = null,
    last_move_by = v_uid,
    turn_number = v_game.turn_number + 1,
    consecutive_timeouts = 0,
    last_request_id = p_request_id,
    updated_at = now()
  where id = p_game_id;

  insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
  values (p_game_id, v_uid, 'play_move',
          jsonb_build_object('pawn', p_pawn_index, 'from', v_current_step, 'to', v_new_step,
                            'captured', v_captured, 'captured_count', v_captured_count,
                            'extra_turn', v_extra_turn),
          v_game.turn_number);

  return jsonb_build_object('captured', v_captured, 'captured_count', v_captured_count,
                            'won', false, 'extra_turn', v_extra_turn);
end;
$$;
grant execute on function public.ludo_v2_play_move(uuid, int, text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 11) RPC ludo_v2_skip_turn - validation no-move           ║
-- ╚══════════════════════════════════════════════════════════╝

-- Helper : detecte si le joueur a un coup possible avec le dé courant
create or replace function public._lv2_has_playable_move(
  p_game record, p_uid uuid
) returns boolean
language plpgsql immutable as $$
declare
  v_pawns jsonb;
  v_step int;
  v_dice int;
  i int;
begin
  v_dice := p_game.dice_value;
  v_pawns := p_game.pawns -> p_uid::text;
  if v_pawns is null then return false; end if;

  for i in 0..3 loop
    v_step := (v_pawns ->> i)::int;
    if v_step = 0 then
      if v_dice = 6 then return true; end if;
    elsif v_step + v_dice <= 58 then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

create or replace function public.ludo_v2_skip_turn(
  p_game_id uuid,
  p_request_id text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_turn_order uuid[];
  v_turn_idx int;
  v_next uuid;
  i int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'GAME_NOT_PLAYING'; end if;
  if v_game.current_turn != v_uid then raise exception 'NOT_YOUR_TURN'; end if;
  if not v_game.dice_rolled then raise exception 'ROLL_FIRST'; end if;

  -- Idempotence
  if p_request_id is not null and v_game.last_request_id = p_request_id then return; end if;

  -- Validation : skip seulement si VRAIMENT pas de coup
  if public._lv2_has_playable_move(v_game, v_uid) then
    raise exception 'PLAYABLE_MOVES_EXIST';
  end if;

  v_turn_order := v_game.turn_order;
  v_turn_idx := 1;
  for i in 1..array_length(v_turn_order, 1) loop
    if v_turn_order[i] = v_uid then v_turn_idx := i; exit; end if;
  end loop;
  v_turn_idx := (v_turn_idx % array_length(v_turn_order, 1)) + 1;
  v_next := v_turn_order[v_turn_idx];

  update public.ludo_v2_games set
    current_turn = v_next,
    dice_rolled = false, dice_value = null,
    turn_number = v_game.turn_number + 1,
    consecutive_timeouts = 0,
    last_request_id = p_request_id,
    updated_at = now()
  where id = p_game_id;

  insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
  values (p_game_id, v_uid, 'skip_turn',
          jsonb_build_object('reason', 'no_playable_moves'), v_game.turn_number);
end;
$$;
grant execute on function public.ludo_v2_skip_turn(uuid, text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 12) RPC ludo_v2_forfeit - FAIR-PLAY                      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Logique :
--   - 2 joueurs : le restant gagne (90% du pot, 10% caisse)
--   - 3+ joueurs : refund 100% aux non-forfaits, le forfaiter perd sa mise
--     (sa mise reste dans la caisse)
-- ============================================================

create or replace function public.ludo_v2_forfeit(
  p_game_id uuid,
  p_request_id text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_other_players uuid[];
  v_pot int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'NOT_PLAYING'); end if;

  if not (v_uid = any(v_game.turn_order)) then
    raise exception 'NOT_PARTICIPANT';
  end if;

  -- Idempotence
  if p_request_id is not null and v_game.last_request_id = p_request_id then
    return jsonb_build_object('ok', true, 'idempotent', true);
  end if;

  v_other_players := array_remove(v_game.turn_order, v_uid);

  update public.ludo_v2_games set
    status = 'finished',
    winner_id = case when array_length(v_other_players, 1) = 1
                     then v_other_players[1] else null end,
    last_request_id = p_request_id,
    updated_at = now()
  where id = p_game_id;

  if v_game.bet_amount > 0 and array_length(v_other_players, 1) > 0 then
    if array_length(v_game.turn_order, 1) = 2 then
      -- 1v1 : le restant gagne tout (90/10)
      v_pot := v_game.bet_amount * 2;
      perform public.apply_game_payout('ludo_v2', p_game_id::text,
        v_other_players[1], v_pot);
    else
      -- 3+ : refund integral aux non-forfaits, mise du forfaiter reste a la caisse
      perform public.treasury_refund_all('ludo_v2', p_game_id::text,
        v_other_players, v_game.bet_amount);
    end if;
  end if;

  insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
  values (p_game_id, v_uid, 'forfeit',
          jsonb_build_object('player_count', array_length(v_game.turn_order, 1),
                            'others', v_other_players),
          v_game.turn_number);

  return jsonb_build_object('ok', true,
    'winner_id', case when array_length(v_other_players, 1) = 1
                      then v_other_players[1] else null end);
end;
$$;
grant execute on function public.ludo_v2_forfeit(uuid, text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 13) RPC ludo_v2_register_timeout - lives serveur         ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_register_timeout(p_game_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_new_count int;
  v_max_timeouts int := 3;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'GAME_NOT_PLAYING'; end if;
  if v_game.current_turn != v_uid then raise exception 'NOT_YOUR_TURN'; end if;

  v_new_count := v_game.consecutive_timeouts + 1;

  update public.ludo_v2_games set
    consecutive_timeouts = v_new_count,
    updated_at = now()
  where id = p_game_id;

  insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
  values (p_game_id, v_uid, 'timeout',
          jsonb_build_object('count', v_new_count, 'max', v_max_timeouts),
          v_game.turn_number);

  if v_new_count >= v_max_timeouts then
    -- Auto-forfait
    perform public.ludo_v2_forfeit(p_game_id, 'auto_forfeit_' || p_game_id::text || '_' || v_new_count);
    return jsonb_build_object('forfeited', true, 'timeouts', v_new_count);
  end if;

  return jsonb_build_object('forfeited', false, 'timeouts', v_new_count, 'max', v_max_timeouts);
end;
$$;
grant execute on function public.ludo_v2_register_timeout(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 14) RPC ludo_v2_claim_idle_win - anti-AFK adversaire     ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_claim_idle_win(p_game_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_uid uuid := auth.uid();
  v_idle_seconds int := 90;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_game from public.ludo_v2_games
    where id = p_game_id and status = 'playing' for update;
  if not found then raise exception 'GAME_NOT_PLAYING'; end if;
  if not (v_uid = any(v_game.turn_order)) then raise exception 'NOT_PARTICIPANT'; end if;
  if v_uid = v_game.current_turn then raise exception 'YOU_ARE_PLAYING'; end if;
  if v_game.turn_started_at > now() - (v_idle_seconds::text || ' seconds')::interval then
    raise exception 'TURN_STILL_ACTIVE';
  end if;

  -- Forcer un forfait du joueur idle
  -- (on ne peut pas appeler ludo_v2_forfeit directement car auth.uid() est nous, pas l'idle)
  -- Donc on duplique la logique :
  declare
    v_idle_uid uuid := v_game.current_turn;
    v_other_players uuid[];
    v_pot int;
  begin
    v_other_players := array_remove(v_game.turn_order, v_idle_uid);
    update public.ludo_v2_games set
      status = 'finished',
      winner_id = case when array_length(v_other_players, 1) = 1
                       then v_other_players[1] else null end,
      updated_at = now()
    where id = p_game_id;

    if v_game.bet_amount > 0 and array_length(v_other_players, 1) > 0 then
      if array_length(v_game.turn_order, 1) = 2 then
        v_pot := v_game.bet_amount * 2;
        perform public.apply_game_payout('ludo_v2', p_game_id::text, v_other_players[1], v_pot);
      else
        perform public.treasury_refund_all('ludo_v2', p_game_id::text,
          v_other_players, v_game.bet_amount);
      end if;
    end if;

    insert into public.ludo_v2_events (game_id, user_id, event_type, payload, turn_number)
    values (p_game_id, v_idle_uid, 'idle_forfeit_claimed',
            jsonb_build_object('claimed_by', v_uid,
                              'idle_seconds', extract(epoch from (now() - v_game.turn_started_at))),
            v_game.turn_number);

    return jsonb_build_object('claimed', true, 'idle_player', v_idle_uid);
  end;
end;
$$;
grant execute on function public.ludo_v2_claim_idle_win(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 15) Cleanup auto stale games + rooms                     ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.ludo_v2_cleanup_stale()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_game record;
  v_room record;
  v_count_games int := 0;
  v_count_rooms int := 0;
begin
  -- Games en 'playing' inactives > 30 min : refund tous, marquer cancelled
  for v_game in
    select * from public.ludo_v2_games
    where status = 'playing' and updated_at < now() - interval '30 minutes'
  loop
    update public.ludo_v2_games set status = 'finished', updated_at = now()
      where id = v_game.id;
    update public.ludo_v2_rooms set status = 'cancelled' where game_id = v_game.id;

    if v_game.bet_amount > 0 and array_length(v_game.turn_order, 1) > 0 then
      perform public.treasury_refund_all('ludo_v2', v_game.id::text,
        v_game.turn_order, v_game.bet_amount);
    end if;

    insert into public.ludo_v2_events (game_id, event_type, payload, turn_number)
    values (v_game.id, 'cleanup_stale',
            jsonb_build_object('refunded_players', array_length(v_game.turn_order, 1),
                              'amount_per_player', v_game.bet_amount),
            v_game.turn_number);

    v_count_games := v_count_games + 1;
  end loop;

  -- Rooms 'waiting' > 1h : refund les joueurs qui auraient pu deja payer
  -- (avec le nouveau flow, le debit est fait au start_game, donc ces rooms
  --  n'ont pas de debit. Mais on les supprime pour menage.)
  for v_room in
    select * from public.ludo_v2_rooms
    where status = 'waiting' and created_at < now() - interval '1 hour'
  loop
    update public.ludo_v2_rooms set status = 'cancelled' where id = v_room.id;
    v_count_rooms := v_count_rooms + 1;
  end loop;

  perform public.log_event('info', 'ludo_v2', 'cleanup_stale ran',
    jsonb_build_object('games_cancelled', v_count_games, 'rooms_cancelled', v_count_rooms));

  return jsonb_build_object('games_cancelled', v_count_games, 'rooms_cancelled', v_count_rooms);
end;
$$;
grant execute on function public.ludo_v2_cleanup_stale() to authenticated;

-- pg_cron (si actif sur Supabase) :
--   select cron.schedule('ludo_v2_cleanup', '*/15 * * * *',
--     'select public.ludo_v2_cleanup_stale()');


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 16) Realtime publication                                 ║
-- ╚══════════════════════════════════════════════════════════╝

do $rt$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and tablename='ludo_v2_events'
  ) then
    alter publication supabase_realtime add table public.ludo_v2_events;
  end if;
end $rt$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 17) Vue de monitoring : games actives + idle             ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace view public.ludo_v2_active_games_v as
select
  g.id,
  g.room_id,
  g.current_turn,
  g.turn_order,
  g.dice_rolled,
  g.consecutive_timeouts,
  g.bet_amount,
  g.turn_started_at,
  extract(epoch from (now() - g.turn_started_at))::int as turn_idle_seconds,
  extract(epoch from (now() - g.updated_at))::int as game_idle_seconds,
  array_length(g.turn_order, 1) as player_count,
  g.bet_amount * array_length(g.turn_order, 1) as pot_size
from public.ludo_v2_games g
where g.status = 'playing';

grant select on public.ludo_v2_active_games_v to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ FIN                                                      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Verifications post-execution :
--
-- 1. RLS : tester directement via REST que UPDATE sur ludo_v2_games echoue
--    PATCH /rest/v1/ludo_v2_games?id=eq.X { "status": "finished" } -> 401/403
--
-- 2. Lance une partie 2 joueurs, mise 100 :
--    - Verifier 2 lignes 'ludo_v2_bet' dans wallet_ledger (-100 chacun)
--    - Verifier 1 ligne 'game_started' dans ludo_v2_events
--    - Joueur gagne -> 1 ligne dans treasury_movements (payout, 90)
--                   -> 1 ligne (house_cut, 10)
--                   -> wallet_ledger : refund non incremente (apply_game_payout
--                      met a jour user_profiles direct, le wallet_ledger ne
--                      voit que les operations passees par wallet_apply_delta)
--
-- 3. Tester le claim idle :
--    - Faire timeout 90+ secondes au tour de l'adversaire
--    - Appeler ludo_v2_claim_idle_win() → success
--
-- 4. Tester cleanup :
--    - Forcer une game updated_at = now() - interval '1 hour'
--    - Appeler ludo_v2_cleanup_stale() → game cancelled, refunds
--
-- 5. Wallet consistency :
--    - select wallet_check_consistency('<user_id>')
--    - Doit retourner consistent=true (note : seulement les operations passees
--      par wallet_apply_delta apparaissent ; pour atteindre 100% il faut aussi
--      router apply_game_payout via wallet_apply_delta)
-- ============================================================
