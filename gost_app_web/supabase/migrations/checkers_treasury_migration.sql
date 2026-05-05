-- ============================================================
-- CHECKERS - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_final_fix.sql.
-- Idempotent : safe to re-run.
--
-- Etat actuel (avant migration) :
--   - Logique argent ENTIEREMENT cote Flutter (deductCoins/addCoinsToUser)
--   - Trigger checkers_treasury_hook appelait admin_treasury_take_commission
--     (DROP par treasury_final_fix.sql) -> Checkers cassé en l'etat
--
-- Cette migration :
--   1. DROP le trigger casse + sa fonction
--   2. Cree 4 RPCs treasury :
--      - checkers_create_room : debit hote + insert room
--      - checkers_join_room   : debit guest + update room (status='playing')
--      - checkers_finish_game : payout vainqueur via apply_game_payout
--      - checkers_draw_game   : refund 100% sur match nul (sans commission)
--
-- Logique payout :
--   - Pot = bet_amount * 2 (1v1)
--   - Vainqueur : apply_game_payout(pot) -> 90% vainqueur, 10% caisse
--   - Match nul : treasury_refund_all([host, guest], bet) -> 100% chacun
-- ============================================================

-- ============================================================
-- 0a) REALTIME : ajout de checkers_rooms a la publication
-- ============================================================
-- BUG FIX : sans ca, les updates du game_state ne sont PAS pousses
-- aux abonnes -> le coup d'un joueur n'apparait pas chez l'autre, et la
-- fin de partie (winner_id, status='finished') ne propage pas non plus.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'checkers_rooms'
  ) then
    alter publication supabase_realtime add table public.checkers_rooms;
  end if;
end$$;

-- REPLICA IDENTITY FULL : envoie le row entier dans payload.newRecord
-- (sans ca, certaines colonnes peuvent manquer dans les UPDATE events).
alter table public.checkers_rooms replica identity full;

-- ============================================================
-- 0b) DROP trigger + fonction casses
-- ============================================================
do $$
declare r record;
begin
  for r in
    select t.tgname, c.relname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_class c on c.oid = t.tgrelid
    where p.proname = 'checkers_treasury_hook'
      and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on public.%I',
                   r.tgname, r.relname);
  end loop;
end$$;

drop function if exists public.checkers_treasury_hook() cascade;

-- ============================================================
-- 1) checkers_create_room - debit hote + insert
-- ============================================================
create or replace function public.checkers_create_room(
  p_bet_amount int,
  p_is_private boolean,
  p_host_color text default 'red'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_username text;
  v_code text;
  v_room_id uuid;
  v_room record;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_bet_amount < 0 then
    raise exception 'INVALID_BET';
  end if;

  -- Code prive unique
  if p_is_private then
    loop
      v_code := upper(substr(md5(random()::text), 1, 6));
      exit when not exists (
        select 1 from public.checkers_rooms where private_code = v_code
      );
    end loop;
  end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  -- Insert room d'abord (besoin du room_id pour le log treasury)
  insert into public.checkers_rooms
    (host_id, host_username, host_color, bet_amount, pot,
     is_private, private_code, status)
    values (v_uid, v_username, coalesce(p_host_color, 'red'),
            p_bet_amount, p_bet_amount,
            p_is_private, v_code, 'waiting')
    returning id into v_room_id;

  -- ===== TREASURY MIGRATION =====
  if p_bet_amount > 0 then
    perform public.treasury_place_bet(
      'checkers', v_room_id::text, v_uid, p_bet_amount
    );
  end if;

  select * into v_room from public.checkers_rooms where id = v_room_id;
  return to_jsonb(v_room);
end;
$function$;

grant execute on function public.checkers_create_room(int, boolean, text) to authenticated;

-- ============================================================
-- 2) checkers_join_room - debit guest + update
-- ============================================================
create or replace function public.checkers_join_room(
  p_room_id uuid,
  p_initial_state jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_username text;
  v_guest_color text;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_room from public.checkers_rooms
    where id = p_room_id for update;
  if not found then
    raise exception 'ROOM_NOT_FOUND';
  end if;
  if v_room.status != 'waiting' then
    raise exception 'ROOM_NOT_WAITING';
  end if;
  if v_room.guest_id is not null then
    raise exception 'ROOM_FULL';
  end if;
  if v_room.host_id = v_uid then
    raise exception 'CANNOT_JOIN_OWN_ROOM';
  end if;

  -- ===== TREASURY MIGRATION =====
  if v_room.bet_amount > 0 then
    perform public.treasury_place_bet(
      'checkers', p_room_id::text, v_uid, v_room.bet_amount
    );
  end if;

  select coalesce(username, 'Joueur') into v_username
    from public.user_profiles where id = v_uid;

  v_guest_color := case when v_room.host_color = 'red' then 'black' else 'red' end;

  update public.checkers_rooms set
    guest_id = v_uid,
    guest_username = v_username,
    guest_color = v_guest_color,
    status = 'playing',
    pot = bet_amount * 2,
    game_state = p_initial_state
    where id = p_room_id;

  select * into v_room from public.checkers_rooms where id = p_room_id;
  return to_jsonb(v_room);
end;
$function$;

grant execute on function public.checkers_join_room(uuid, jsonb) to authenticated;

-- ============================================================
-- 3) checkers_finish_game - payout vainqueur
-- ============================================================
-- Appelee quand un joueur a gagne (le client envoie le winner_id).
-- p_winner_id doit etre host_id ou guest_id de la room.
create or replace function public.checkers_finish_game(
  p_room_id uuid,
  p_winner_id uuid,
  p_final_state jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_room record;
  v_pot int;
begin
  select * into v_room from public.checkers_rooms
    where id = p_room_id for update;
  if not found then
    raise exception 'ROOM_NOT_FOUND';
  end if;
  if v_room.status != 'playing' then
    raise exception 'ROOM_NOT_PLAYING';
  end if;
  if p_winner_id is null then
    raise exception 'WINNER_REQUIRED';
  end if;
  if p_winner_id != v_room.host_id and p_winner_id != v_room.guest_id then
    raise exception 'INVALID_WINNER';
  end if;

  v_pot := coalesce(v_room.pot, 0);

  -- ===== TREASURY MIGRATION =====
  -- Payout : 90% vainqueur, 10% caisse
  if v_pot > 0 then
    perform public.apply_game_payout(
      'checkers', p_room_id::text, p_winner_id, v_pot
    );
  end if;

  update public.checkers_rooms set
    status = 'finished',
    winner_id = p_winner_id,
    game_state = coalesce(p_final_state, game_state)
    where id = p_room_id;

  return jsonb_build_object(
    'success', true,
    'winner_id', p_winner_id,
    'pot', v_pot,
    'net_payout', floor(v_pot * 0.90)::int
  );
end;
$function$;

grant execute on function public.checkers_finish_game(uuid, uuid, jsonb) to authenticated;

-- ============================================================
-- 4) checkers_draw_game - match nul, refund 100%
-- ============================================================
-- Aucune commission sur match nul (politique uniforme du systeme).
create or replace function public.checkers_draw_game(
  p_room_id uuid,
  p_final_state jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_room record;
  v_user_ids uuid[];
begin
  select * into v_room from public.checkers_rooms
    where id = p_room_id for update;
  if not found then
    raise exception 'ROOM_NOT_FOUND';
  end if;
  if v_room.status != 'playing' then
    raise exception 'ROOM_NOT_PLAYING';
  end if;

  -- Refund 100% chaque participant (pas de commission)
  if v_room.bet_amount > 0 then
    v_user_ids := array_remove(
      array[v_room.host_id, v_room.guest_id], null);
    if array_length(v_user_ids, 1) > 0 then
      perform public.treasury_refund_all(
        'checkers', p_room_id::text, v_user_ids, v_room.bet_amount
      );
    end if;
  end if;

  update public.checkers_rooms set
    status = 'finished',
    winner_id = null,
    game_state = coalesce(p_final_state, game_state)
    where id = p_room_id;

  return jsonb_build_object(
    'success', true,
    'draw', true,
    'refund_per_player', v_room.bet_amount
  );
end;
$function$;

grant execute on function public.checkers_draw_game(uuid, jsonb) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution :
--
-- Scenario 1 (1v1, bet 100, host gagne) :
--   - checkers_create_room  : host -100, caisse +100
--   - checkers_join_room    : guest -100, caisse +200, pot=200
--   - checkers_finish_game(host) : apply_game_payout(200)
--                                  -> host +180 (90%), caisse +20 (10%)
--   - Bilan host  : -100 + 180 = +80
--   - Bilan guest : -100
--   - Bilan caisse round : +200 - 180 = +20 (= 10% du pot)
--
-- Scenario 2 (match nul) :
--   - host -100, guest -100, caisse +200
--   - checkers_draw_game : treasury_refund_all([host, guest], 100)
--                          -> host +100, guest +100, caisse -200
--   - Bilan caisse = 0 (aucune commission)
--   - Bilan joueurs = 0 chacun
--
-- Scenario 3 (bet 0, partie gratuite) :
--   - Aucun mouvement treasury, juste room/game_state
--   - finish_game : pot=0 -> apply_game_payout skip
--
-- Notes :
-- - Le trigger checkers_treasury_hook (qui appelait l'ancienne
--   admin_treasury_take_commission DROP) est maintenant supprime.
--   Toute la logique passe par les RPCs ci-dessus.
-- - Le client Flutter doit etre mis a jour pour utiliser ces RPCs
--   au lieu des appels directs deductCoins/addCoinsToUser.
