-- ============================================================
-- COINFLIP - Cleanup rooms abandonnees + refund
-- ============================================================
-- A executer apres coinflip_treasury_migration.sql.
-- Idempotent.
--
-- Bug fixe :
--   Si un createur cree une room mais personne ne la rejoint, sa mise
--   reste bloquee a la caisse indefiniment. Cette fonction parcourt les
--   rooms 'waiting' anciennes (> 1h) et refund le createur.
-- ============================================================

create or replace function public.coinflip_cleanup_stale_rooms()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room record;
  v_count int := 0;
begin
  for v_room in
    select * from public.coinflip_rooms
    where status = 'waiting'
      and created_at < now() - interval '1 hour'
  loop
    -- Refund 100% au createur (pas de commission sur abandon)
    if v_room.bet_amount > 0 then
      perform public.treasury_refund_all(
        'coinflip', v_room.id::text,
        array[v_room.host_id], v_room.bet_amount
      );
    end if;

    -- Marquer la room comme cancelled (plus visible cote client)
    update public.coinflip_rooms
      set status = 'cancelled', updated_at = now()
      where id = v_room.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.coinflip_cleanup_stale_rooms() to authenticated;

-- Pour activer cron (si pg_cron) :
--   select cron.schedule('cf-cleanup', '0 * * * *',
--     'select public.coinflip_cleanup_stale_rooms()');
