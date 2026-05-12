-- ============================================================
-- SOLITAIRE MULTIJOUEUR V2 — COMPLET (forfait + nul + cancel)
-- ============================================================
-- Complète solitaire_multi_v2_ledger.sql avec :
--   1. solitaire_multi_forfeit  : un joueur quitte pendant la partie
--   2. solitaire_multi_finalize : fin de partie avec gagnant(s) multiples
--                                  (single winner OU tie avec split du pot)
--   3. solitaire_multi_cancel_room : annulation totale + refund tous
--   4. payouts idempotent (request_id par winner)
-- ============================================================

-- ============================================================
-- 0. Pré-requis : colonne updated_at sur solitaire_rooms
-- ============================================================
alter table public.solitaire_rooms
  add column if not exists updated_at timestamptz not null default now();

-- Backfill pour les rows existantes
update public.solitaire_rooms
   set updated_at = coalesce(updated_at, created_at, now())
 where updated_at is null;

-- Trigger auto pour updated_at sur UPDATE
create or replace function public._solitaire_rooms_set_updated_at()
returns trigger language plpgsql as $$
begin
  NEW.updated_at = now();
  return NEW;
end; $$;

drop trigger if exists trg_solitaire_rooms_updated_at on public.solitaire_rooms;
create trigger trg_solitaire_rooms_updated_at
  before update on public.solitaire_rooms
  for each row execute function public._solitaire_rooms_set_updated_at();

-- ============================================================
-- 1. solitaire_multi_forfeit — joueur quitte la partie en cours
-- ============================================================
-- Règle :
--   - Si la game est en 'waiting' (pas encore lancée) → refund + retire
--     (= cancel partiel : on retire l'user, les autres restent)
--   - Si la game est en 'playing' → FORFAIT (mise perdue, game continue)
--   - Si après le forfait il ne reste que 1 joueur non-forfeited → ce
--     joueur gagne le pot solo (commission 10%)
--   - Si tous les joueurs ont forfeited → game cancelled, pot reste en
--     game_treasury (rare, mais évité par le check 1-restant)
-- ============================================================
create or replace function public.solitaire_multi_forfeit(
  p_room_id text
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_players jsonb;
  v_player jsonb;
  v_remaining_count int := 0;
  v_remaining_uid uuid;
  v_pot bigint;
  v_cut bigint;
  v_net bigint;
  v_winner_payout jsonb;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  -- Lock la row room
  select * into v_room from solitaire_rooms
   where id = p_room_id::uuid for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status not in ('waiting','playing') then
    return jsonb_build_object('skipped', true, 'state', v_room.status);
  end if;

  v_players := coalesce(v_room.game_state -> 'players', '[]'::jsonb);

  -- Vérifie que l'user est dans les players
  if not exists (
    select 1 from jsonb_array_elements(v_players) p
     where p->>'id' = v_uid::text
  ) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  -- ===========================================================
  -- CAS WAITING : refund + retirer le user de la room
  -- ===========================================================
  if v_room.status = 'waiting' then
    perform _ledger_post(
      v_uid, v_room.bet_amount, 'refund',
      'solitaire_multi_leave_waiting:' || p_room_id || ':' || v_uid::text,
      'solitaire_multi', p_room_id,
      jsonb_build_object('reason', 'leave_before_start'));

    update game_treasury
       set balance = greatest(0, balance - v_room.bet_amount),
           total_paid_out = total_paid_out + v_room.bet_amount,
           updated_at = now()
     where id = 1;

    -- Retire le user des players
    v_players := (
      select coalesce(jsonb_agg(p), '[]'::jsonb)
        from jsonb_array_elements(v_players) p
       where p->>'id' != v_uid::text
    );

    -- Si plus aucun player → cancel room totale
    if jsonb_array_length(v_players) = 0 then
      update solitaire_rooms set status = 'cancelled', updated_at = now()
       where id = p_room_id::uuid;
      return jsonb_build_object('left', true, 'state', 'cancelled', 'refund', v_room.bet_amount);
    end if;

    -- Sinon : la room reste, current_players décrémenté
    update solitaire_rooms set
      current_players = greatest(0, current_players - 1),
      pot = greatest(0, pot - v_room.bet_amount),
      game_state = jsonb_set(v_room.game_state, '{players}', v_players),
      updated_at = now()
    where id = p_room_id::uuid;

    return jsonb_build_object('left', true, 'state', 'waiting', 'refund', v_room.bet_amount);
  end if;

  -- ===========================================================
  -- CAS PLAYING : FORFAIT (mise perdue, game continue)
  -- ===========================================================
  -- Marque le user comme forfeited dans game_state.players
  v_players := (
    select coalesce(jsonb_agg(
      case when p->>'id' = v_uid::text
           then jsonb_set(p, '{forfeited}', 'true')
           else p
      end
    ), '[]'::jsonb)
    from jsonb_array_elements(v_players) p
  );

  -- Compte les non-forfeited
  select count(*) into v_remaining_count
    from jsonb_array_elements(v_players) p
   where coalesce((p->>'forfeited')::boolean, false) = false;

  -- ===========================================================
  -- 1 SEUL RESTANT : il gagne le pot par défaut (forfait des autres)
  -- ===========================================================
  if v_remaining_count = 1 then
    select (p->>'id')::uuid into v_remaining_uid
      from jsonb_array_elements(v_players) p
     where coalesce((p->>'forfeited')::boolean, false) = false
     limit 1;

    v_pot := v_room.pot;
    v_cut := floor(v_pot * 0.10)::bigint;
    v_net := v_pot - v_cut;

    -- Pay winner
    perform _ledger_post(
      v_remaining_uid, v_net, 'payout',
      'solitaire_multi_payout:' || p_room_id,
      'solitaire_multi', p_room_id,
      jsonb_build_object('pot', v_pot, 'commission', v_cut, 'reason', 'forfeit_lone_winner'));

    -- Treasury & admin commission
    update game_treasury
       set balance = balance - v_pot,
           total_paid_out = total_paid_out + v_pot,
           updated_at = now()
     where id = 1;

    if v_cut > 0 then
      update admin_treasury
         set balance = balance + v_cut, total_earned = total_earned + v_cut,
             updated_at = now()
       where id = 1;
      if not found then
        insert into admin_treasury(id, balance, total_earned, total_withdrawn)
          values (1, v_cut, v_cut, 0);
      end if;
    end if;

    -- Marque la room comme finished
    update solitaire_rooms set
      status = 'finished',
      game_state = jsonb_set(v_room.game_state, '{players}', v_players),
      updated_at = now()
    where id = p_room_id::uuid;

    return jsonb_build_object(
      'forfeited', true,
      'state', 'finished',
      'lone_winner', v_remaining_uid,
      'paid', v_net);
  end if;

  -- ===========================================================
  -- 0 RESTANT : tous ont quitté → REFUND TOUT LE MONDE
  -- (la maison ne garde rien si aucune partie n'a vraiment été jouée
  -- jusqu'au bout — c'est UX-juste)
  -- ===========================================================
  if v_remaining_count = 0 then
    -- Refund chaque joueur (idempotent par player+room)
    declare v_p jsonb; v_puid uuid;
    begin
      for v_p in select * from jsonb_array_elements(v_room.game_state -> 'players') loop
        v_puid := (v_p->>'id')::uuid;
        begin
          perform _ledger_post(
            v_puid, v_room.bet_amount, 'refund',
            'solitaire_multi_all_forfeit_refund:' || p_room_id || ':' || v_puid::text,
            'solitaire_multi', p_room_id,
            jsonb_build_object('reason', 'all_players_forfeited'));
        exception when others then null;
        end;
      end loop;
    end;

    -- Treasury : sortie totale (pot intégralement refundé)
    update game_treasury
       set balance = greatest(0, balance - v_room.pot),
           total_paid_out = total_paid_out + v_room.pot,
           updated_at = now()
     where id = 1;

    update solitaire_rooms set
      status = 'cancelled',
      game_state = jsonb_set(v_room.game_state, '{players}', v_players),
      updated_at = now()
    where id = p_room_id::uuid;
    return jsonb_build_object(
      'forfeited', true,
      'state', 'cancelled_all_forfeit_refunded',
      'refunded_total', v_room.pot);
  end if;

  -- ===========================================================
  -- 2+ RESTANTS : game continue
  -- ===========================================================
  update solitaire_rooms set
    game_state = jsonb_set(v_room.game_state, '{players}', v_players),
    updated_at = now()
  where id = p_room_id::uuid;

  return jsonb_build_object(
    'forfeited', true, 'state', 'playing', 'remaining', v_remaining_count);
end; $$;
revoke all on function public.solitaire_multi_forfeit(text) from public, anon;
grant execute on function public.solitaire_multi_forfeit(text) to authenticated;

-- ============================================================
-- 2. solitaire_multi_finalize — fin normale (1 ou plusieurs gagnants)
-- ============================================================
-- Règles :
--   - p_winner_ids contient les UUIDs des gagnants (1 ou plusieurs si tie)
--   - Si 1 gagnant : il prend pot - 10% commission
--   - Si plusieurs gagnants (égalité) : pot - 10% commission, divisé equal
--   - Si liste vide : tout le monde forfeit / cancelled → pot reste
-- ============================================================
create or replace function public.solitaire_multi_finalize(
  p_room_id    text,
  p_winner_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_pot bigint;
  v_cut bigint;
  v_total_payout bigint;
  v_per_winner bigint;
  v_winners_count int;
  v_winner uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_room from solitaire_rooms where id = p_room_id::uuid for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status = 'finished' then
    return jsonb_build_object('idempotent', true, 'state', 'already_finished');
  end if;
  if v_room.status not in ('waiting','playing') then
    return jsonb_build_object('skipped', true, 'state', v_room.status);
  end if;

  -- Vérifier que l'user appelant est un participant (sinon vol possible)
  if not exists (
    select 1 from jsonb_array_elements(v_room.game_state -> 'players') p
     where p->>'id' = v_uid::text
  ) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  v_winners_count := coalesce(array_length(p_winner_ids, 1), 0);

  -- ===========================================================
  -- PAS DE GAGNANTS : refund TOUS les joueurs (pas la maison)
  -- ===========================================================
  if v_winners_count = 0 then
    declare v_p jsonb; v_puid uuid;
    begin
      for v_p in select * from jsonb_array_elements(v_room.game_state -> 'players') loop
        v_puid := (v_p->>'id')::uuid;
        begin
          perform _ledger_post(
            v_puid, v_room.bet_amount, 'refund',
            'solitaire_multi_no_winner_refund:' || p_room_id || ':' || v_puid::text,
            'solitaire_multi', p_room_id,
            jsonb_build_object('reason', 'no_winner_refund'));
        exception when others then null;
        end;
      end loop;
    end;
    update game_treasury
       set balance = greatest(0, balance - v_room.pot),
           total_paid_out = total_paid_out + v_room.pot,
           updated_at = now()
     where id = 1;
    update solitaire_rooms set status = 'cancelled', updated_at = now()
     where id = p_room_id::uuid;
    return jsonb_build_object('finalized', true, 'state', 'cancelled_no_winner_refunded',
                              'refunded_total', v_room.pot);
  end if;

  v_pot := v_room.pot;

  -- ===========================================================
  -- ÉGALITÉ (2+ winners) : RÉGLE SPÉCIALE
  -- Chaque gagnant tied récupère sa MISE ORIGINALE (pas de commission)
  -- → Les joueurs NON-tied (perdants) perdent leur mise (qui reste à
  --   la maison comme commission de fait).
  -- → Pas de penalty injuste pour ceux qui ont fait égalité.
  -- ===========================================================
  if v_winners_count > 1 then
    foreach v_winner in array p_winner_ids loop
      perform _ledger_post(
        v_winner, v_room.bet_amount, 'refund',
        'solitaire_multi_tie_refund:' || p_room_id || ':' || v_winner::text,
        'solitaire_multi', p_room_id,
        jsonb_build_object(
          'reason', 'tie_each_gets_back_bet',
          'tied_winners', v_winners_count,
          'bet_amount', v_room.bet_amount));
    end loop;

    -- Treasury : sortie = bet × nombre de tied winners (pas pot total)
    update game_treasury
       set balance = greatest(0, balance - (v_room.bet_amount * v_winners_count)),
           total_paid_out = total_paid_out + (v_room.bet_amount * v_winners_count),
           updated_at = now()
     where id = 1;

    -- Le reste du pot (mises des perdants non-tied) → admin_treasury
    declare v_remainder bigint;
    begin
      v_remainder := v_pot - (v_room.bet_amount * v_winners_count);
      if v_remainder > 0 then
        update admin_treasury
           set balance = balance + v_remainder,
               total_earned = total_earned + v_remainder,
               updated_at = now()
         where id = 1;
        if not found then
          insert into admin_treasury(id, balance, total_earned, total_withdrawn)
            values (1, v_remainder, v_remainder, 0);
        end if;
        -- game_treasury sort le remainder vers admin
        update game_treasury
           set balance = greatest(0, balance - v_remainder),
               total_paid_out = total_paid_out + v_remainder,
               updated_at = now()
         where id = 1;
      end if;
    end;

    update solitaire_rooms set status = 'finished', updated_at = now()
     where id = p_room_id::uuid;

    return jsonb_build_object(
      'finalized', true,
      'state', 'finished_tie',
      'winners', to_jsonb(p_winner_ids),
      'pot', v_pot,
      'is_tie', true,
      'each_tied_gets', v_room.bet_amount,
      'note', 'Tied players got their bets back; losers'' bets went to house.');
  end if;

  -- ===========================================================
  -- 1 SEUL GAGNANT : règle normale (pot - 10% commission)
  -- ===========================================================
  v_cut := floor(v_pot * 0.10)::bigint;
  v_total_payout := v_pot - v_cut;
  v_per_winner := v_total_payout;  -- 1 seul gagnant donc total

  perform _ledger_post(
    p_winner_ids[1], v_per_winner, 'payout',
    'solitaire_multi_payout:' || p_room_id || ':' || p_winner_ids[1]::text,
    'solitaire_multi', p_room_id,
    jsonb_build_object('pot', v_pot, 'commission', v_cut));

  update game_treasury
     set balance = balance - v_pot,
         total_paid_out = total_paid_out + v_pot,
         updated_at = now()
   where id = 1;

  if v_cut > 0 then
    update admin_treasury
       set balance = balance + v_cut, total_earned = total_earned + v_cut,
           updated_at = now()
     where id = 1;
    if not found then
      insert into admin_treasury(id, balance, total_earned, total_withdrawn)
        values (1, v_cut, v_cut, 0);
    end if;
  end if;

  update solitaire_rooms set status = 'finished', updated_at = now()
   where id = p_room_id::uuid;

  return jsonb_build_object(
    'finalized', true,
    'state', 'finished',
    'winners', to_jsonb(p_winner_ids),
    'pot', v_pot,
    'commission', v_cut,
    'per_winner', v_per_winner,
    'is_tie', false);
end; $$;
revoke all on function public.solitaire_multi_finalize(text, uuid[]) from public, anon;
grant execute on function public.solitaire_multi_finalize(text, uuid[]) to authenticated;

-- ============================================================
-- 3. solitaire_multi_cancel_room — annulation totale (host kill switch)
-- ============================================================
-- Réservé au host. Refund TOUS les players, room → cancelled.
-- Utilisé pendant 'waiting' uniquement (pendant playing → forfeit logic).
-- ============================================================
create or replace function public.solitaire_multi_cancel_room(
  p_room_id text
) returns jsonb
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_room record;
  v_player jsonb;
  v_player_uid uuid;
  v_count int := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;

  select * into v_room from solitaire_rooms where id = p_room_id::uuid for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;

  if v_room.host_id != v_uid then
    raise exception 'ONLY_HOST_CAN_CANCEL';
  end if;
  if v_room.status != 'waiting' then
    raise exception 'CANNOT_CANCEL_RUNNING_GAME';
  end if;

  -- Refund tous les players
  for v_player in select * from jsonb_array_elements(v_room.game_state -> 'players') loop
    v_player_uid := (v_player->>'id')::uuid;
    perform _ledger_post(
      v_player_uid, v_room.bet_amount, 'refund',
      'solitaire_multi_cancel:' || p_room_id || ':' || v_player_uid::text,
      'solitaire_multi', p_room_id,
      jsonb_build_object('reason', 'host_cancelled'));
    v_count := v_count + 1;
  end loop;

  -- Treasury : sortie totale
  update game_treasury
     set balance = greatest(0, balance - (v_room.bet_amount * v_count)),
         total_paid_out = total_paid_out + (v_room.bet_amount * v_count),
         updated_at = now()
   where id = 1;

  update solitaire_rooms set status = 'cancelled', updated_at = now()
   where id = p_room_id::uuid;

  return jsonb_build_object(
    'cancelled', true,
    'players_refunded', v_count,
    'total_refunded', v_room.bet_amount * v_count);
end; $$;
revoke all on function public.solitaire_multi_cancel_room(text) from public, anon;
grant execute on function public.solitaire_multi_cancel_room(text) to authenticated;

-- ============================================================
-- 4. Cleanup : rooms zombies (waiting > 30 min sans activité)
-- ============================================================
create or replace function public.solitaire_multi_cleanup_stale()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare
  v_room record;
  v_player jsonb;
  v_player_uid uuid;
  v_count int := 0;
begin
  for v_room in
    select * from solitaire_rooms
     where status = 'waiting'
       and updated_at < now() - interval '30 minutes'
     for update skip locked
     limit 50
  loop
    -- Refund tous
    for v_player in select * from jsonb_array_elements(v_room.game_state -> 'players') loop
      v_player_uid := (v_player->>'id')::uuid;
      begin
        perform _ledger_post(
          v_player_uid, v_room.bet_amount, 'refund',
          'solitaire_multi_stale:' || v_room.id::text || ':' || v_player_uid::text,
          'solitaire_multi', v_room.id::text,
          jsonb_build_object('reason', 'stale_room_cleanup'));
      exception when others then null;
      end;
    end loop;

    update game_treasury
       set balance = greatest(0, balance - (v_room.bet_amount * v_room.current_players)),
           total_paid_out = total_paid_out + (v_room.bet_amount * v_room.current_players),
           updated_at = now()
     where id = 1;

    update solitaire_rooms set status = 'cancelled', updated_at = now()
     where id = v_room.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function public.solitaire_multi_cleanup_stale() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'solitaire-multi-cleanup-stale';
    perform cron.schedule('solitaire-multi-cleanup-stale', '*/10 * * * *',
      $cron$ select public.solitaire_multi_cleanup_stale(); $cron$);
    raise notice 'Cron solitaire-multi-cleanup-stale schedulé (toutes les 10 min)';
  end if;
end $$;

-- ============================================================
-- 4b. Cleanup : DELETE des rooms finished/cancelled > 24h
-- (évite le grossissement infini de la table)
-- ============================================================
create or replace function public.solitaire_multi_purge_old()
returns int
language plpgsql security definer set search_path=public, extensions
as $$
declare v_count int;
begin
  with deleted as (
    delete from solitaire_rooms
     where status in ('finished','cancelled')
       and updated_at < now() - interval '24 hours'
    returning 1
  )
  select count(*) into v_count from deleted;
  return v_count;
end $$;
revoke all on function public.solitaire_multi_purge_old() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job where jobname = 'solitaire-multi-purge-old';
    perform cron.schedule('solitaire-multi-purge-old', '0 4 * * *',
      $cron$ select public.solitaire_multi_purge_old(); $cron$);
    raise notice 'Cron solitaire-multi-purge-old schedulé (chaque jour à 4h)';
  end if;
end $$;

-- ============================================================
-- 5. Drop l'ancienne solitaire_multi_payout (remplacée par finalize)
-- ============================================================
drop function if exists public.solitaire_multi_payout(text, uuid, bigint, numeric);

-- ============================================================
-- 6. Vue admin : sessions multi en cours / historique
-- ============================================================
create or replace view public.solitaire_multi_metrics_v as
select
  count(*) filter (where status = 'waiting') as rooms_waiting,
  count(*) filter (where status = 'playing') as rooms_playing,
  count(*) filter (where status = 'finished' and updated_at > now() - interval '1 hour') as wins_per_hour,
  count(*) filter (where status = 'cancelled' and updated_at > now() - interval '1 hour') as cancels_per_hour,
  coalesce(sum(pot) filter (where status = 'finished' and updated_at > now() - interval '24 hours'), 0) as volume_24h
from solitaire_rooms;
revoke all on solitaire_multi_metrics_v from public, anon, authenticated;
