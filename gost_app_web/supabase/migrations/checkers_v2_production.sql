-- ============================================================
-- CHECKERS V2 — PRODUCTION (server-side authoritative engine)
-- ============================================================
-- A executer APRES checkers_treasury_migration.sql + checkers_anti_cheat_v1.sql.
-- Idempotent.
--
-- CONTENU :
--   1. DROP checkers_update_state (faille majeure)
--   2. Schema additions (current_jump_from, last_request_id, turn_started_at)
--   3. Helper SQL : _checkers_compute_legal_moves(board, color)
--   4. RPC checkers_play_move(p_room_id, p_from_r, p_from_c, p_to_r, p_to_c, p_request_id)
--      → moteur complet validation + multi-capture + promotion dame
--   5. Events log table checkers_events
--   6. RPC checkers_register_timeout (server-side lives)
--   7. RPC checkers_claim_idle_win (anti-AFK adversaire)
--   8. RPC checkers_cleanup_stale (cron-friendly)
--   9. RLS strict
-- ============================================================


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) DROP la RPC trop permissive                            ║
-- ╚══════════════════════════════════════════════════════════╝

drop function if exists public.checkers_update_state(uuid, jsonb) cascade;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) Schema additions                                       ║
-- ╚══════════════════════════════════════════════════════════╝

alter table public.checkers_rooms
  add column if not exists current_jump_from jsonb,        -- {row,col} si multi-capture en cours
  add column if not exists last_request_id text,           -- idempotence
  add column if not exists turn_started_at timestamptz default now(),
  add column if not exists consecutive_timeouts int not null default 0,
  add column if not exists state_version int not null default 0;

-- Trigger : reset consecutive_timeouts + update turn_started_at au changement de tour
create or replace function public.checkers_track_turn_change()
returns trigger language plpgsql as $$
begin
  if new.game_state is distinct from old.game_state then
    new.state_version := old.state_version + 1;
  end if;
  if (new.game_state ->> 'currentTurn') is distinct from (old.game_state ->> 'currentTurn') then
    new.turn_started_at := now();
    new.consecutive_timeouts := 0;
    new.current_jump_from := null;
  end if;
  return new;
end;
$$;

drop trigger if exists checkers_turn_change_trg on public.checkers_rooms;
create trigger checkers_turn_change_trg
  before update on public.checkers_rooms
  for each row execute function public.checkers_track_turn_change();


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) Events log                                             ║
-- ╚══════════════════════════════════════════════════════════╝

create table if not exists public.checkers_events (
  id          bigserial primary key,
  room_id     uuid not null references public.checkers_rooms(id) on delete cascade,
  user_id     uuid,
  event_type  text not null,                  -- 'play_move' | 'timeout' | 'forfeit' | 'idle_claim' | 'cleanup'
  payload     jsonb default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists idx_checkers_events_room on public.checkers_events(room_id, created_at);
create index if not exists idx_checkers_events_user on public.checkers_events(user_id, created_at desc);

alter table public.checkers_events enable row level security;
drop policy if exists "ce_select_participants" on public.checkers_events;
create policy "ce_select_participants" on public.checkers_events for select to authenticated using (
  exists (
    select 1 from public.checkers_rooms r
    where r.id = checkers_events.room_id
      and (auth.uid() = r.host_id or auth.uid() = r.guest_id)
  )
  or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin'
);

drop policy if exists "ce_no_direct_write" on public.checkers_events;
create policy "ce_no_direct_write" on public.checkers_events for all to authenticated using (false) with check (false);


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) Helper : _checkers_get_piece(board, r, c)              ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public._checkers_get_piece(p_board jsonb, p_row int, p_col int)
returns jsonb
language sql immutable as $$
  select case
    when p_row < 0 or p_row > 7 or p_col < 0 or p_col > 7 then null
    else (p_board -> p_row -> p_col)
  end;
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 5) Helper : _checkers_set_piece(board, r, c, piece)       ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public._checkers_set_piece(
  p_board jsonb, p_row int, p_col int, p_piece jsonb
) returns jsonb
language sql immutable as $$
  select jsonb_set(p_board, array[p_row::text, p_col::text], coalesce(p_piece, 'null'::jsonb));
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 6) Helper : _checkers_has_capture_from(board, r, c)       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Retourne true si depuis (r,c) il existe au moins une capture possible
-- pour le pion à cette position (basé sur sa couleur et son type).

create or replace function public._checkers_has_capture_from(
  p_board jsonb, p_row int, p_col int
) returns boolean
language plpgsql immutable as $$
declare
  v_piece jsonb;
  v_color text;
  v_is_king boolean;
  v_dirs int[][] := array[array[-1,-1], array[-1,1], array[1,-1], array[1,1]];
  v_d int[];
  v_mid_r int; v_mid_c int;
  v_land_r int; v_land_c int;
  v_mid_piece jsonb;
  v_land_piece jsonb;
  i int;
begin
  v_piece := public._checkers_get_piece(p_board, p_row, p_col);
  if v_piece is null then return false; end if;

  v_color := v_piece ->> 'color';
  v_is_king := (v_piece ->> 'type') = 'king';

  -- Captures = 4 directions toujours autorisees (regle classique)
  for i in 1..4 loop
    v_d := v_dirs[i:i][1:2];
    v_mid_r := p_row + v_d[1];
    v_mid_c := p_col + v_d[2];
    v_land_r := p_row + (v_d[1] * 2);
    v_land_c := p_col + (v_d[2] * 2);

    if v_land_r < 0 or v_land_r > 7 or v_land_c < 0 or v_land_c > 7 then continue; end if;

    v_mid_piece := public._checkers_get_piece(p_board, v_mid_r, v_mid_c);
    v_land_piece := public._checkers_get_piece(p_board, v_land_r, v_land_c);

    if v_mid_piece is not null
       and (v_mid_piece ->> 'color') != v_color
       and v_land_piece is null
    then
      return true;
    end if;
  end loop;

  return false;
end;
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 7) Helper : _checkers_color_has_any_capture                ║
-- ╚══════════════════════════════════════════════════════════╝
-- True si la couleur a au moins une capture obligatoire sur le board.

create or replace function public._checkers_color_has_any_capture(
  p_board jsonb, p_color text
) returns boolean
language plpgsql immutable as $$
declare
  r int; c int;
  v_piece jsonb;
begin
  for r in 0..7 loop
    for c in 0..7 loop
      v_piece := public._checkers_get_piece(p_board, r, c);
      if v_piece is not null and (v_piece ->> 'color') = p_color then
        if public._checkers_has_capture_from(p_board, r, c) then return true; end if;
      end if;
    end loop;
  end loop;
  return false;
end;
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 8) Helper : _checkers_color_has_any_move                   ║
-- ╚══════════════════════════════════════════════════════════╝
-- True si la couleur a au moins un move legal (capture ou simple).
-- Si false → no_legal_moves → la couleur a perdu.

create or replace function public._checkers_color_has_any_move(
  p_board jsonb, p_color text
) returns boolean
language plpgsql immutable as $$
declare
  r int; c int;
  v_piece jsonb;
  v_is_king boolean;
  v_simple_dirs int[][];
  v_d int[];
  i int; nr int; nc int;
begin
  -- D'abord les captures (priorite)
  if public._checkers_color_has_any_capture(p_board, p_color) then return true; end if;

  -- Sinon les moves simples
  for r in 0..7 loop
    for c in 0..7 loop
      v_piece := public._checkers_get_piece(p_board, r, c);
      if v_piece is null or (v_piece ->> 'color') != p_color then continue; end if;
      v_is_king := (v_piece ->> 'type') = 'king';

      if v_is_king then
        v_simple_dirs := array[array[-1,-1], array[-1,1], array[1,-1], array[1,1]];
      elsif p_color = 'red' then
        v_simple_dirs := array[array[-1,-1], array[-1,1]];
      else
        v_simple_dirs := array[array[1,-1], array[1,1]];
      end if;

      for i in 1..array_length(v_simple_dirs, 1) loop
        v_d := v_simple_dirs[i:i][1:2];
        nr := r + v_d[1]; nc := c + v_d[2];
        if nr >= 0 and nr <= 7 and nc >= 0 and nc <= 7
           and public._checkers_get_piece(p_board, nr, nc) is null then
          return true;
        end if;
      end loop;
    end loop;
  end loop;
  return false;
end;
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 9) Helper : _checkers_count_pieces(board, color)           ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public._checkers_count_pieces(
  p_board jsonb, p_color text
) returns int
language plpgsql immutable as $$
declare r int; c int; v_piece jsonb; v_count int := 0;
begin
  for r in 0..7 loop
    for c in 0..7 loop
      v_piece := public._checkers_get_piece(p_board, r, c);
      if v_piece is not null and (v_piece ->> 'color') = p_color then
        v_count := v_count + 1;
      end if;
    end loop;
  end loop;
  return v_count;
end;
$$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 10) RPC PRINCIPALE : checkers_play_move                   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Effectue UN saut (simple ou capture). Le client doit rappeler la RPC
-- pour chaque saut additionnel d'une multi-capture.
--
-- Validation complete cote serveur :
--   1. Caller = participant
--   2. Status = 'playing'
--   3. C'est le tour de la couleur du caller
--   4. La piece a (from_r, from_c) appartient au caller
--   5. Le mouvement est legal (direction, distance, case libre)
--   6. Si capture obligatoire dans le board, le move DOIT etre une capture
--   7. Si multi-capture en cours (current_jump_from set), le move DOIT etre depuis cette case
--   8. Idempotence par request_id
--
-- Retour : jsonb {
--   success: bool,
--   captured: bool,
--   captured_count: int,
--   promoted: bool,
--   must_continue: bool,    -- true si encore une capture obligatoire depuis dst
--   game_over: bool,
--   winner_color: text?
-- }
-- ============================================================

create or replace function public.checkers_play_move(
  p_room_id uuid,
  p_from_r int,
  p_from_c int,
  p_to_r int,
  p_to_c int,
  p_request_id text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_state jsonb;
  v_board jsonb;
  v_my_color text;        -- 'red' ou 'black'
  v_from_piece jsonb;
  v_to_piece jsonb;
  v_dr int;
  v_dc int;
  v_abs_dr int;
  v_abs_dc int;
  v_is_capture boolean := false;
  v_is_simple boolean := false;
  v_mid_r int;
  v_mid_c int;
  v_mid_piece jsonb;
  v_must_be_capture boolean;
  v_is_king boolean;
  v_promoted boolean := false;
  v_new_piece jsonb;
  v_new_board jsonb;
  v_red_count int;
  v_black_count int;
  v_winner_color text := null;
  v_game_over boolean := false;
  v_must_continue boolean := false;
  v_next_turn text;
  v_new_state jsonb;
  v_winner_id uuid := null;
  v_pot int;
  v_simple_dirs int[][];
  v_d int[];
  i int; nr int; nc int;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  -- 1. Lock la room
  select * into v_room from public.checkers_rooms
    where id = p_room_id and status = 'playing' for update;
  if not found then raise exception 'ROOM_NOT_PLAYING'; end if;

  -- 2. Caller = participant
  if v_uid != v_room.host_id and v_uid != v_room.guest_id then
    raise exception 'NOT_PARTICIPANT';
  end if;

  -- 3. Idempotence
  if p_request_id is not null and v_room.last_request_id = p_request_id then
    return jsonb_build_object('success', true, 'idempotent', true);
  end if;

  -- 4. Determiner la couleur du caller
  v_my_color := case
    when v_uid = v_room.host_id then v_room.host_color
    when v_uid = v_room.guest_id then v_room.guest_color
    else null
  end;
  if v_my_color is null then raise exception 'NO_COLOR_ASSIGNED'; end if;

  v_state := v_room.game_state;
  if v_state is null then raise exception 'NO_GAME_STATE'; end if;

  v_board := v_state -> 'board';
  if v_board is null then raise exception 'NO_BOARD'; end if;

  -- 5. C'est mon tour ?
  if (v_state ->> 'currentTurn') != v_my_color then
    raise exception 'NOT_YOUR_TURN: current=%, you=%',
      v_state ->> 'currentTurn', v_my_color;
  end if;

  -- 6. Validation des coordonnees
  if p_from_r < 0 or p_from_r > 7 or p_from_c < 0 or p_from_c > 7
     or p_to_r < 0 or p_to_r > 7 or p_to_c < 0 or p_to_c > 7 then
    raise exception 'OUT_OF_BOARD';
  end if;

  -- 7. La piece source m'appartient ?
  v_from_piece := public._checkers_get_piece(v_board, p_from_r, p_from_c);
  if v_from_piece is null then raise exception 'NO_PIECE_AT_FROM'; end if;
  if (v_from_piece ->> 'color') != v_my_color then raise exception 'NOT_YOUR_PIECE'; end if;

  v_is_king := (v_from_piece ->> 'type') = 'king';

  -- 8. Si multi-capture en cours, la piece source doit etre celle qui a saute
  if v_room.current_jump_from is not null then
    if (v_room.current_jump_from ->> 'row')::int != p_from_r
       or (v_room.current_jump_from ->> 'col')::int != p_from_c then
      raise exception 'MUST_CONTINUE_FROM_LAST_JUMP';
    end if;
  end if;

  -- 9. La case destination est libre ?
  v_to_piece := public._checkers_get_piece(v_board, p_to_r, p_to_c);
  if v_to_piece is not null then raise exception 'DEST_NOT_EMPTY'; end if;

  -- 10. Validation de la direction et distance
  v_dr := p_to_r - p_from_r;
  v_dc := p_to_c - p_from_c;
  v_abs_dr := abs(v_dr);
  v_abs_dc := abs(v_dc);

  if v_abs_dr != v_abs_dc then raise exception 'NOT_DIAGONAL'; end if;
  if v_abs_dr = 0 then raise exception 'NO_MOVEMENT'; end if;

  -- 11. Detecter si simple ou capture
  if v_abs_dr = 1 then
    -- Move simple
    v_is_simple := true;

    -- Pion simple : direction respectee
    if not v_is_king then
      if v_my_color = 'red' and v_dr >= 0 then raise exception 'WRONG_DIRECTION'; end if;
      if v_my_color = 'black' and v_dr <= 0 then raise exception 'WRONG_DIRECTION'; end if;
    end if;

    -- Si une capture est obligatoire pour la couleur, on ne peut PAS faire un simple move
    -- (sauf si on est en multi-capture déjà entamée — auquel cas le move attendu doit etre une capture)
    v_must_be_capture := public._checkers_color_has_any_capture(v_board, v_my_color);
    if v_must_be_capture then raise exception 'CAPTURE_OBLIGATORY'; end if;

    -- Multi-capture en cours interdit le simple move
    if v_room.current_jump_from is not null then
      raise exception 'MUST_CONTINUE_CAPTURE';
    end if;

  elsif v_abs_dr = 2 then
    -- Capture
    v_is_capture := true;
    v_mid_r := p_from_r + (v_dr / 2);
    v_mid_c := p_from_c + (v_dc / 2);
    v_mid_piece := public._checkers_get_piece(v_board, v_mid_r, v_mid_c);

    if v_mid_piece is null then raise exception 'NO_PIECE_TO_CAPTURE'; end if;
    if (v_mid_piece ->> 'color') = v_my_color then raise exception 'CANT_CAPTURE_OWN'; end if;

    -- Pion simple : capture autorisee dans toutes directions (regle classique)
    -- Note : si tu veux la regle stricte (pion simple ne capture qu'en avant),
    -- decommenter :
    -- if not v_is_king then
    --   if v_my_color = 'red' and v_dr >= 0 then raise exception 'WRONG_CAPTURE_DIR'; end if;
    --   if v_my_color = 'black' and v_dr <= 0 then raise exception 'WRONG_CAPTURE_DIR'; end if;
    -- end if;

  else
    raise exception 'INVALID_DISTANCE: %', v_abs_dr;
  end if;

  -- 12. Appliquer le move
  v_new_board := public._checkers_set_piece(v_board, p_from_r, p_from_c, null);

  if v_is_capture then
    v_new_board := public._checkers_set_piece(v_new_board, v_mid_r, v_mid_c, null);
  end if;

  -- Promotion en dame si arrivee a la rangee finale
  if not v_is_king then
    if v_my_color = 'red' and p_to_r = 0 then
      v_promoted := true;
    elsif v_my_color = 'black' and p_to_r = 7 then
      v_promoted := true;
    end if;
  end if;

  v_new_piece := jsonb_build_object(
    'color', v_my_color,
    'type', case when v_is_king or v_promoted then 'king' else 'normal' end
  );
  v_new_board := public._checkers_set_piece(v_new_board, p_to_r, p_to_c, v_new_piece);

  -- 13. Recompter les pieces
  v_red_count := public._checkers_count_pieces(v_new_board, 'red');
  v_black_count := public._checkers_count_pieces(v_new_board, 'black');

  -- 14. Verifier victoire
  if v_red_count = 0 then
    v_game_over := true;
    v_winner_color := 'black';
  elsif v_black_count = 0 then
    v_game_over := true;
    v_winner_color := 'red';
  end if;

  -- 15. Si capture sans game over : le joueur DOIT continuer si encore une capture possible depuis dst
  --     (sauf si la promotion vient juste de se faire, auquel cas certaines regles disent "stop".
  --      Ici on garde la regle stricte : multi-capture obligatoire jusqu'a la fin, meme apres promotion.)
  if v_is_capture and not v_game_over then
    if public._checkers_has_capture_from(v_new_board, p_to_r, p_to_c) then
      v_must_continue := true;
    end if;
  end if;

  -- 16. Determiner le prochain tour
  if v_game_over then
    v_next_turn := v_my_color;  -- pas important
  elsif v_must_continue then
    v_next_turn := v_my_color;  -- on rejoue
  else
    v_next_turn := case when v_my_color = 'red' then 'black' else 'red' end;

    -- Verifier si l'autre joueur peut jouer
    if not public._checkers_color_has_any_move(v_new_board, v_next_turn) then
      v_game_over := true;
      v_winner_color := v_my_color;
    end if;
  end if;

  -- 17. Determiner le winner_id si game_over
  if v_game_over and v_winner_color is not null then
    v_winner_id := case
      when v_winner_color = v_room.host_color then v_room.host_id
      when v_winner_color = v_room.guest_color then v_room.guest_id
      else null
    end;
  end if;

  -- 18. Construire le nouvel etat
  v_new_state := jsonb_build_object(
    'board', v_new_board,
    'currentTurn', v_next_turn,
    'isGameOver', v_game_over,
    'winner', v_winner_color,
    'winnerUserId', v_winner_id,
    'redCount', v_red_count,
    'blackCount', v_black_count
  );

  -- 19. Update + idempotence + jump tracking
  update public.checkers_rooms set
    game_state = v_new_state,
    last_request_id = p_request_id,
    current_jump_from = case
      when v_must_continue then jsonb_build_object('row', p_to_r, 'col', p_to_c)
      else null
    end,
    status = case when v_game_over then 'finished' else status end,
    winner_id = case when v_game_over then v_winner_id else winner_id end
  where id = p_room_id;

  -- 20. Logger l'event
  insert into public.checkers_events (room_id, user_id, event_type, payload)
  values (p_room_id, v_uid, 'play_move', jsonb_build_object(
    'from', jsonb_build_array(p_from_r, p_from_c),
    'to', jsonb_build_array(p_to_r, p_to_c),
    'capture', v_is_capture,
    'promoted', v_promoted,
    'must_continue', v_must_continue,
    'game_over', v_game_over,
    'winner', v_winner_color
  ));

  -- 21. Si game_over, distribuer le pot
  if v_game_over and v_winner_id is not null and v_room.bet_amount > 0 then
    v_pot := v_room.bet_amount * 2;
    perform public.apply_game_payout('checkers', p_room_id::text, v_winner_id, v_pot);
  end if;

  return jsonb_build_object(
    'success', true,
    'captured', v_is_capture,
    'captured_count', case when v_is_capture then 1 else 0 end,
    'promoted', v_promoted,
    'must_continue', v_must_continue,
    'game_over', v_game_over,
    'winner_color', v_winner_color,
    'winner_id', v_winner_id
  );
end;
$$;

grant execute on function public.checkers_play_move(uuid, int, int, int, int, text) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 11) RPC checkers_register_timeout (lives serveur)         ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.checkers_register_timeout(p_room_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_my_color text;
  v_new_count int;
  v_max_timeouts int := 3;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_room from public.checkers_rooms
    where id = p_room_id and status = 'playing' for update;
  if not found then raise exception 'ROOM_NOT_PLAYING'; end if;

  v_my_color := case
    when v_uid = v_room.host_id then v_room.host_color
    when v_uid = v_room.guest_id then v_room.guest_color
    else null
  end;
  if v_my_color is null then raise exception 'NOT_PARTICIPANT'; end if;

  if (v_room.game_state ->> 'currentTurn') != v_my_color then
    raise exception 'NOT_YOUR_TURN';
  end if;

  v_new_count := v_room.consecutive_timeouts + 1;

  update public.checkers_rooms set consecutive_timeouts = v_new_count where id = p_room_id;

  insert into public.checkers_events (room_id, user_id, event_type, payload)
  values (p_room_id, v_uid, 'timeout', jsonb_build_object('count', v_new_count, 'max', v_max_timeouts));

  if v_new_count >= v_max_timeouts then
    -- Auto-forfait
    perform public.checkers_finish_game(
      p_room_id,
      case when v_uid = v_room.host_id then v_room.guest_id else v_room.host_id end,
      v_room.game_state
    );
    return jsonb_build_object('forfeited', true, 'timeouts', v_new_count);
  end if;

  return jsonb_build_object('forfeited', false, 'timeouts', v_new_count, 'max', v_max_timeouts);
end;
$$;

grant execute on function public.checkers_register_timeout(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 12) RPC checkers_claim_idle_win (anti-AFK)                ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.checkers_claim_idle_win(p_room_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_idle_seconds int := 90;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_room from public.checkers_rooms
    where id = p_room_id and status = 'playing' for update;
  if not found then raise exception 'ROOM_NOT_PLAYING'; end if;

  if v_uid != v_room.host_id and v_uid != v_room.guest_id then
    raise exception 'NOT_PARTICIPANT';
  end if;

  -- Verifier que l'adversaire est idle
  declare
    v_my_color text := case when v_uid = v_room.host_id then v_room.host_color else v_room.guest_color end;
  begin
    if (v_room.game_state ->> 'currentTurn') = v_my_color then
      raise exception 'YOU_ARE_PLAYING';
    end if;
  end;

  if v_room.turn_started_at > now() - (v_idle_seconds::text || ' seconds')::interval then
    raise exception 'TURN_STILL_ACTIVE';
  end if;

  -- Forcer la finition avec moi comme winner
  perform public.checkers_finish_game(p_room_id, v_uid, v_room.game_state);

  insert into public.checkers_events (room_id, user_id, event_type, payload)
  values (p_room_id, v_uid, 'idle_claim', jsonb_build_object(
    'idle_seconds', extract(epoch from (now() - v_room.turn_started_at))
  ));

  return jsonb_build_object('claimed', true);
end;
$$;

grant execute on function public.checkers_claim_idle_win(uuid) to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 13) checkers_cleanup_stale enrichi                        ║
-- ╚══════════════════════════════════════════════════════════╝

create or replace function public.checkers_cleanup_stale_playing()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_room record;
  v_count int := 0;
  v_user_ids uuid[];
begin
  for v_room in
    select * from public.checkers_rooms
    where status = 'playing'
      and turn_started_at < now() - interval '30 minutes'
  loop
    if v_room.bet_amount > 0 then
      v_user_ids := array_remove(array[v_room.host_id, v_room.guest_id], null);
      if array_length(v_user_ids, 1) > 0 then
        perform public.treasury_refund_all(
          'checkers', v_room.id::text, v_user_ids, v_room.bet_amount
        );
      end if;
    end if;

    update public.checkers_rooms set status = 'cancelled' where id = v_room.id;

    insert into public.checkers_events (room_id, event_type, payload)
    values (v_room.id, 'cleanup', jsonb_build_object('reason', 'stale_30min'));

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.checkers_cleanup_stale_playing() to authenticated;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ 14) Realtime publication                                  ║
-- ╚══════════════════════════════════════════════════════════╝

do $rt$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'checkers_events'
  ) then
    alter publication supabase_realtime add table public.checkers_events;
  end if;
end $rt$;


-- ╔══════════════════════════════════════════════════════════╗
-- ║ FIN                                                       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Cron suggere :
--   select cron.schedule('checkers_cleanup', '*/15 * * * *',
--     'select public.checkers_cleanup_stale_playing()');
--
-- Tests :
--   1. Lance une partie 2j, mise 100
--   2. Joueur A joue un move illegal via REST → erreur (RLS bloque)
--   3. Joueur A joue via checkers_play_move(...) avec pawn de couleur opposee → NOT_YOUR_PIECE
--   4. Joueur A joue alors que c'est tour de B → NOT_YOUR_TURN
--   5. Capture obligatoire ignoree → CAPTURE_OBLIGATORY
--   6. Multi-capture : 2 sauts de suite → must_continue=true entre les 2,
--      tour ne change pas
--   7. Promotion en dame quand arrivee rangee 0 (red) ou 7 (black)
--   8. Game over quand l'adversaire n'a plus de move legal
-- ============================================================
