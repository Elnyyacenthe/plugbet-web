-- ============================================================
-- BLACKJACK - Cleanup rooms abandonnees + refund
-- ============================================================
-- A executer apres blackjack_treasury_migration.sql.
-- Idempotent.
--
-- Bug fixe :
--   1. Rooms 'waiting' jamais demarrees (host quitte) -> mise bloquee
--   2. Games 'playing' abandonnees (tous joueurs partis) -> mises bloquees
-- ============================================================

create or replace function public.blackjack_cleanup_stale_rooms()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room record;
  v_user_ids uuid[];
  v_count int := 0;
begin
  -- Rooms 'waiting' > 1h : refund tous les joueurs deja inscrits
  for v_room in
    select * from public.blackjack_rooms
    where status = 'waiting'
      and created_at < now() - interval '1 hour'
  loop
    if v_room.bet_amount > 0 then
      select array_agg(user_id) into v_user_ids
        from public.blackjack_room_players where room_id = v_room.id;
      v_user_ids := coalesce(v_user_ids, array[]::uuid[]);

      if array_length(v_user_ids, 1) > 0 then
        perform public.treasury_refund_all(
          'blackjack', v_room.id::text, v_user_ids, v_room.bet_amount
        );
      end if;
    end if;

    update public.blackjack_rooms
      set status = 'cancelled'
      where id = v_room.id;

    v_count := v_count + 1;
  end loop;

  -- Games 'playing' > 1h : refund + cancel
  for v_room in
    select r.* from public.blackjack_rooms r
    where r.status = 'playing'
      and r.created_at < now() - interval '1 hour'
  loop
    if v_room.bet_amount > 0 then
      select array_agg(user_id) into v_user_ids
        from public.blackjack_room_players where room_id = v_room.id;
      v_user_ids := coalesce(v_user_ids, array[]::uuid[]);

      if array_length(v_user_ids, 1) > 0 then
        perform public.treasury_refund_all(
          'blackjack', v_room.id::text, v_user_ids, v_room.bet_amount
        );
      end if;
    end if;

    update public.blackjack_rooms
      set status = 'cancelled'
      where id = v_room.id;

    update public.blackjack_games
      set status = 'cancelled'
      where room_id = v_room.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.blackjack_cleanup_stale_rooms() to authenticated;

-- pg_cron :
--   select cron.schedule('bj-cleanup', '0 * * * *',
--     'select public.blackjack_cleanup_stale_rooms()');
