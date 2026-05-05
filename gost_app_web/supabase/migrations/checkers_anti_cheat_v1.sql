-- ============================================================
-- CHECKERS - Anti-cheat V1 (validation basique + RLS)
-- ============================================================
-- A executer APRES checkers_treasury_migration.sql.
-- Idempotent.
--
-- Ce fichier durcit les validations cote serveur :
--   1. RLS : seuls host/guest peuvent UPDATE leur room
--   2. RPC checkers_update_state : remplace les UPDATE directs cote client
--   3. checkers_finish_game : valide la coherence winner vs game_state
--
-- LIMITATION (acceptee en V1) :
--   La logique des moves (deplacements, captures, promotions) reste cote
--   client. Un joueur peut donc forger un game_state via la RPC
--   checkers_update_state. La V2 devra reimplementer la logique en SQL
--   pour fermer cette derniere faille.
-- ============================================================

-- ============================================================
-- 1) RLS - seuls les participants peuvent UPDATE/SELECT
-- ============================================================
alter table public.checkers_rooms enable row level security;

-- SELECT : tout authentifie (necessaire pour realtime + lobby)
drop policy if exists "checkers_rooms_select_authenticated" on public.checkers_rooms;
create policy "checkers_rooms_select_authenticated"
  on public.checkers_rooms for select
  to authenticated using (true);

-- UPDATE direct : INTERDIT cote client (seules les RPCs SECURITY DEFINER peuvent ecrire)
-- Note : les RPCs bypassent RLS, donc elles peuvent toujours ecrire.
drop policy if exists "checkers_rooms_no_direct_update" on public.checkers_rooms;
create policy "checkers_rooms_no_direct_update"
  on public.checkers_rooms for update
  to authenticated using (false) with check (false);

-- INSERT direct : INTERDIT (passe par checkers_create_room)
drop policy if exists "checkers_rooms_no_direct_insert" on public.checkers_rooms;
create policy "checkers_rooms_no_direct_insert"
  on public.checkers_rooms for insert
  to authenticated with check (false);

-- DELETE direct : INTERDIT (passe par cleanup serveur)
drop policy if exists "checkers_rooms_no_direct_delete" on public.checkers_rooms;
create policy "checkers_rooms_no_direct_delete"
  on public.checkers_rooms for delete
  to authenticated using (false);

-- ============================================================
-- 2) RPC checkers_update_state - point d'entree controle pour game_state
-- ============================================================
-- Remplace les .update({'game_state': ...}) directs cote client.
-- Verifie que :
--   - Le caller est host ou guest
--   - La room est en 'playing'
--   - Le state envoye n'a pas isGameOver=true (pour eviter les claims sauvages)
create or replace function public.checkers_update_state(
  p_room_id uuid,
  p_game_state jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_room record;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_room from public.checkers_rooms
    where id = p_room_id;
  if not found then
    raise exception 'ROOM_NOT_FOUND';
  end if;

  if v_uid != v_room.host_id and v_uid != coalesce(v_room.guest_id, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'NOT_PARTICIPANT';
  end if;

  if v_room.status != 'playing' then
    raise exception 'ROOM_NOT_PLAYING';
  end if;

  -- Bloquer les claims "isGameOver:true" via cette RPC.
  -- Pour terminer la partie, il faut passer par checkers_finish_game
  -- (qui valide la coherence winner_id <-> game_state).
  if (p_game_state ->> 'isGameOver')::boolean = true then
    raise exception 'USE_FINISH_GAME_INSTEAD';
  end if;

  update public.checkers_rooms
    set game_state = p_game_state
    where id = p_room_id;
end;
$function$;

grant execute on function public.checkers_update_state(uuid, jsonb) to authenticated;

-- ============================================================
-- 3) checkers_finish_game - validation coherence winner
-- ============================================================
-- Patch : on accepte la finition seulement si :
--   a) Forfait : caller == loser, winner = l'autre joueur
--   b) Win valide : game_state.winnerUserId == p_winner_id
--
-- Note : le scenario (b) reste exploitable si le client envoie un
-- game_state forge via une RPC qu'on ne controle pas (la logique des
-- moves est encore cote client). C'est documente.
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
  v_uid uuid := auth.uid();
  v_room record;
  v_pot int;
  v_state jsonb;
  v_state_winner_uid text;
  v_is_forfeit boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

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

  -- Caller doit etre participant
  if v_uid != v_room.host_id and v_uid != v_room.guest_id then
    raise exception 'NOT_PARTICIPANT';
  end if;

  -- Determine si c'est un forfait (caller declare l'autre comme winner)
  v_is_forfeit := (v_uid != p_winner_id);

  if not v_is_forfeit then
    -- Cas WIN : valider que game_state confirme la victoire claimee
    v_state := coalesce(p_final_state, v_room.game_state);
    if v_state is null then
      raise exception 'NO_GAME_STATE';
    end if;
    if (v_state ->> 'isGameOver')::boolean is not true then
      raise exception 'GAME_NOT_OVER';
    end if;
    v_state_winner_uid := v_state ->> 'winnerUserId';
    if v_state_winner_uid is null or v_state_winner_uid != p_winner_id::text then
      raise exception 'WINNER_MISMATCH: state=%, claimed=%',
        v_state_winner_uid, p_winner_id;
    end if;
  end if;
  -- Cas FORFEIT : pas de validation supplementaire (le forfaiter peut
  -- toujours abandonner, c'est legitime).

  v_pot := coalesce(v_room.pot, 0);

  -- ===== TREASURY PAYOUT =====
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
    'net_payout', floor(v_pot * 0.90)::int,
    'forfeit', v_is_forfeit
  );
end;
$function$;

grant execute on function public.checkers_finish_game(uuid, uuid, jsonb) to authenticated;

-- ============================================================
-- 4) Cleanup : supprimer les rooms en 'playing' abandonnees > 1h
-- ============================================================
-- Une room peut rester bloquee en 'playing' si les 2 joueurs ont kill
-- l'app sans forfait. Cette fonction libere les rooms anciennes en
-- declarant un match nul (refund).
create or replace function public.checkers_cleanup_stale_playing()
returns int
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_room record;
  v_count int := 0;
  v_user_ids uuid[];
begin
  for v_room in
    select * from public.checkers_rooms
    where status = 'playing'
      and updated_at < now() - interval '1 hour'
  loop
    -- Refund 100% chaque participant
    if v_room.bet_amount > 0 then
      v_user_ids := array_remove(
        array[v_room.host_id, v_room.guest_id], null);
      if array_length(v_user_ids, 1) > 0 then
        perform public.treasury_refund_all(
          'checkers', v_room.id::text, v_user_ids, v_room.bet_amount
        );
      end if;
    end if;

    update public.checkers_rooms set
      status = 'cancelled',
      updated_at = now()
      where id = v_room.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$function$;

grant execute on function public.checkers_cleanup_stale_playing() to authenticated;

-- Pour activer le cleanup automatique avec pg_cron (si actif) :
--   select cron.schedule('checkers-cleanup', '0 * * * *',
--     'select public.checkers_cleanup_stale_playing()');

-- ============================================================
-- BONUS : ajouter updated_at sur checkers_rooms si absent
-- ============================================================
-- Necessaire pour le cleanup ci-dessus.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'checkers_rooms'
      and column_name = 'updated_at'
  ) then
    alter table public.checkers_rooms
      add column updated_at timestamptz default now();
    -- Trigger pour auto-update
    create or replace function public.checkers_rooms_touch_updated_at()
    returns trigger language plpgsql as $tg$
    begin
      new.updated_at := now();
      return new;
    end;
    $tg$;

    drop trigger if exists checkers_rooms_touch on public.checkers_rooms;
    create trigger checkers_rooms_touch
      before update on public.checkers_rooms
      for each row execute function public.checkers_rooms_touch_updated_at();
  end if;
end$$;

-- ============================================================
-- FIN
-- ============================================================
-- A faire cote Flutter apres execution :
--   - Remplacer _client.from('checkers_rooms').update({'game_state':...})
--     par _client.rpc('checkers_update_state', params:{...})
--   - Tester : un joueur essaie d'appeler checkers_finish_game
--     avec p_winner_id=self sans avoir joue -> doit echouer 'GAME_NOT_OVER'
-- ============================================================
