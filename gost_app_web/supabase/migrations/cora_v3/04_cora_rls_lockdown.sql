-- ============================================================
-- CORA DICE V3 — RLS LOCKDOWN
-- ============================================================
-- Verrouille les tables : aucune INSERT/UPDATE/DELETE direct.
-- SELECT autorisé uniquement aux participants/contextes légitimes.
-- Toute mutation doit passer par les RPCs SECURITY DEFINER.
-- ============================================================

-- ============================================================
-- 1. cora_rooms
-- ============================================================
alter table public.cora_rooms enable row level security;

drop policy if exists "Users can view public rooms"  on public.cora_rooms;
drop policy if exists "Users can update own rooms"   on public.cora_rooms;
drop policy if exists "Users can delete own rooms"   on public.cora_rooms;
drop policy if exists "Users can insert rooms"       on public.cora_rooms;

-- SELECT : public-waiting OR own OR participating
create policy "rooms_select" on public.cora_rooms for select using (
  (status = 'waiting' and is_private = false)
  or host_id = auth.uid()
  or exists (select 1 from cora_room_players
              where room_id = cora_rooms.id and user_id = auth.uid())
);

-- AUCUNE policy INSERT/UPDATE/DELETE → impossibles côté client.
-- Mutations via : cora_create_room, cora_join_room, cora_submit_roll, cleanup crons.

-- ============================================================
-- 2. cora_games
-- ============================================================
alter table public.cora_games enable row level security;

drop policy if exists "Users can view their games"   on public.cora_games;
drop policy if exists "Users can update their games" on public.cora_games;
drop policy if exists "Users can insert games"       on public.cora_games;

-- SELECT : seulement les joueurs de la room
create policy "games_select_participants" on public.cora_games for select using (
  exists (select 1 from cora_room_players
            where room_id = cora_games.room_id and user_id = auth.uid())
);

-- AUCUNE policy mutation. Mutations via RPCs.

-- ============================================================
-- 3. cora_room_players
-- ============================================================
alter table public.cora_room_players enable row level security;

drop policy if exists "Users can view room players"  on public.cora_room_players;
drop policy if exists "Users can insert themselves"  on public.cora_room_players;
drop policy if exists "Users can update themselves"  on public.cora_room_players;
drop policy if exists "Users can delete themselves"  on public.cora_room_players;

-- SELECT : tous les participants peuvent se voir
create policy "rp_select" on public.cora_room_players for select using (
  exists (select 1 from cora_room_players p2
           where p2.room_id = cora_room_players.room_id and p2.user_id = auth.uid())
);

-- AUCUNE policy INSERT/UPDATE/DELETE → impossibles côté client.
-- Join : cora_join_room. Quit : cora_leave_room. Ready : cora_toggle_ready.

-- ============================================================
-- 4. cora_messages
-- ============================================================
alter table public.cora_messages enable row level security;

drop policy if exists "Users can view messages"   on public.cora_messages;
drop policy if exists "Users can insert messages" on public.cora_messages;

create policy "msg_select" on public.cora_messages for select using (
  exists (select 1 from cora_room_players
           where room_id = cora_messages.room_id and user_id = auth.uid())
);

-- INSERT autorisé : un user peut poster un message dans une room où il est
-- (pas d'écriture non-financière à protéger ici — chat seulement)
create policy "msg_insert_participant" on public.cora_messages for insert with check (
  user_id = auth.uid()
  and exists (select 1 from cora_room_players
               where room_id = cora_messages.room_id and user_id = auth.uid())
);

-- ============================================================
-- 5. game_treasury / admin_treasury : déjà verrouillées par treasury_unified
-- ============================================================
-- Vérification :
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'game_treasury') then
    raise notice 'WARNING: game_treasury sans RLS policies. Vérifie treasury_unified.sql';
  end if;
end $$;

-- ============================================================
-- 6. Révocation des fonctions Cora-internes uniquement
-- ============================================================
-- IMPORTANT : on NE PAS révoque tout le schéma public — les autres jeux
-- (Ludo, Aviator, Roulette, Blackjack, Coinflip, Checkers, Solitaire...)
-- ne sont pas encore migrés en V3 et ont besoin de leurs grants.
--
-- On révoque uniquement les RPCs Cora internes (préfixe `_cora_`) et les
-- fonctions Cora qui doivent rester appelables seulement par le serveur.
-- ============================================================
do $$
declare
  -- Fonctions Cora-V3 qui doivent être PUBLIQUES (gardent leurs grants)
  v_cora_public text[] := array[
    'cora_create_room','cora_join_room','cora_leave_room',
    'cora_toggle_ready','cora_submit_roll','cora_forfeit',
    'cora_get_active','cora_replay_game','cora_my_history',
    'cora_send_message'
  ];
  f record;
begin
  for f in
    select n.nspname || '.' || p.proname as fn,
           p.proname,
           '(' || pg_get_function_identity_arguments(p.oid) || ')' as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and (
        -- Fonctions internes Cora préfixées par _cora_ ou _ledger_post
        p.proname like '\_cora\_%' escape '\'
        or p.proname in ('_ledger_post','cora_place_bet','cora_pay_winner',
                         'cora_refund_participants','cora_cleanup_stale_rooms',
                         'cora_cleanup_stuck_games','cora_scan_fraud_patterns')
      )
      -- Sécurité : ne révoque jamais les RPCs publiques explicites
      and p.proname <> all(v_cora_public)
  loop
    begin
      execute format('revoke execute on function %s%s from authenticated, anon, public',
                     f.fn, f.args);
      raise notice 'Cora internal locked down: %s%s', f.fn, f.args;
    exception when others then
      raise notice 'Skip revoke %s%s: %', f.fn, f.args, sqlerrm;
    end;
  end loop;
end $$;

-- NB : si tu migres d'autres jeux plus tard (Ludo V3, Aviator V3...), tu
-- pourras ajouter leur lockdown dans leur propre fichier de migration en
-- adaptant ce pattern (préfixe + whitelist publique).
