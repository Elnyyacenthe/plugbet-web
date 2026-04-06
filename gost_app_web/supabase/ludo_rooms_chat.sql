-- ============================================================
-- LUDO ROOMS + CHAT - Schema Extension
-- Executer dans Supabase SQL Editor apres ludo_setup.sql
-- Idempotent : peut etre relance sans erreur
-- ============================================================

-- 1. Table des salles
create table if not exists public.ludo_rooms (
  id uuid default gen_random_uuid() primary key,
  code text not null unique,
  host_id uuid references auth.users(id) not null,
  guest_id uuid references auth.users(id),
  bet_amount int not null default 50,
  is_private boolean not null default false,
  status text not null default 'waiting',
  game_id uuid references public.ludo_games(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.ludo_rooms enable row level security;

drop policy if exists "Anyone can read public rooms or own rooms" on public.ludo_rooms;
create policy "Anyone can read public rooms or own rooms"
  on public.ludo_rooms for select using (
    is_private = false
    or auth.uid() = host_id
    or auth.uid() = guest_id
  );

drop policy if exists "Users can create rooms" on public.ludo_rooms;
create policy "Users can create rooms"
  on public.ludo_rooms for insert
  with check (auth.uid() = host_id);

drop policy if exists "Room participants can update" on public.ludo_rooms;
create policy "Room participants can update"
  on public.ludo_rooms for update
  using (auth.uid() = host_id or auth.uid() = guest_id);

drop policy if exists "Host can delete own waiting room" on public.ludo_rooms;
create policy "Host can delete own waiting room"
  on public.ludo_rooms for delete
  using (auth.uid() = host_id and status = 'waiting');

-- Realtime (ignore si deja ajoute)
do $$ begin
  alter publication supabase_realtime add table public.ludo_rooms;
exception when duplicate_object then null;
end $$;

create index if not exists idx_rooms_code on public.ludo_rooms(code);
create index if not exists idx_rooms_status on public.ludo_rooms(status) where status = 'waiting';

-- 2. Table du chat en jeu
create table if not exists public.ludo_chat (
  id uuid default gen_random_uuid() primary key,
  game_id uuid references public.ludo_games(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  message text not null,
  created_at timestamptz default now()
);

alter table public.ludo_chat enable row level security;

drop policy if exists "Game players can read chat" on public.ludo_chat;
create policy "Game players can read chat"
  on public.ludo_chat for select using (
    exists (
      select 1 from public.ludo_games g
      where g.id = game_id
      and (g.player1 = auth.uid() or g.player2 = auth.uid())
    )
  );

drop policy if exists "Game players can send messages" on public.ludo_chat;
create policy "Game players can send messages"
  on public.ludo_chat for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.ludo_games g
      where g.id = game_id
      and (g.player1 = auth.uid() or g.player2 = auth.uid())
    )
  );

-- Realtime (ignore si deja ajoute)
do $$ begin
  alter publication supabase_realtime add table public.ludo_chat;
exception when duplicate_object then null;
end $$;

create index if not exists idx_chat_game on public.ludo_chat(game_id);

-- 3. Fonction: Generer un code unique de 6 caracteres
create or replace function public.generate_room_code()
returns text as $$
declare
  v_code text;
  v_exists boolean;
begin
  loop
    v_code := upper(substr(md5(random()::text), 1, 6));
    select exists(select 1 from public.ludo_rooms where code = v_code) into v_exists;
    exit when not v_exists;
  end loop;
  return v_code;
end;
$$ language plpgsql;

-- 4. Fonction: Creer une salle
create or replace function public.create_ludo_room(p_bet_amount int, p_is_private boolean)
returns json as $$
declare
  v_code text;
  v_room_id uuid;
begin
  if (select coins from public.user_profiles where id = auth.uid()) < p_bet_amount then
    raise exception 'Solde insuffisant';
  end if;

  v_code := public.generate_room_code();

  insert into public.ludo_rooms (code, host_id, bet_amount, is_private)
  values (v_code, auth.uid(), p_bet_amount, p_is_private)
  returning id into v_room_id;

  return json_build_object('room_id', v_room_id, 'code', v_code);
end;
$$ language plpgsql security definer;

-- 5. Fonction: Rejoindre une salle par code
create or replace function public.join_ludo_room(p_code text)
returns uuid as $$
declare
  v_room record;
  v_game_id uuid;
begin
  select * into v_room from public.ludo_rooms
  where code = upper(p_code) and status = 'waiting';

  if not found then
    raise exception 'Salle introuvable ou deja pleine';
  end if;

  if v_room.host_id = auth.uid() then
    raise exception 'Vous ne pouvez pas rejoindre votre propre salle';
  end if;

  if (select coins from public.user_profiles where id = auth.uid()) < v_room.bet_amount then
    raise exception 'Solde insuffisant';
  end if;

  -- Debiter les deux joueurs
  update public.user_profiles set coins = coins - v_room.bet_amount where id = v_room.host_id;
  update public.user_profiles set coins = coins - v_room.bet_amount where id = auth.uid();

  -- Creer la partie
  insert into public.ludo_games (
    player1, player2, current_turn, bet_amount, game_state, status
  ) values (
    v_room.host_id, auth.uid(), v_room.host_id, v_room.bet_amount,
    jsonb_build_object(
      'pawns', jsonb_build_object(
        v_room.host_id::text, '[0,0,0,0]'::jsonb,
        auth.uid()::text, '[0,0,0,0]'::jsonb
      ),
      'lastDice', 0,
      'hasRolled', false
    ),
    'playing'
  ) returning id into v_game_id;

  -- Mettre a jour la salle
  update public.ludo_rooms
  set guest_id = auth.uid(), status = 'playing', game_id = v_game_id, updated_at = now()
  where id = v_room.id;

  return v_game_id;
end;
$$ language plpgsql security definer;

-- 6. Fonction: Annuler une partie (bug systeme) - Rembourser les deux joueurs
create or replace function public.cancel_ludo_game(p_game_id uuid)
returns void as $$
declare
  v_bet int;
  v_player1 uuid;
  v_player2 uuid;
  v_status text;
begin
  select bet_amount, player1, player2, status
  into v_bet, v_player1, v_player2, v_status
  from public.ludo_games
  where id = p_game_id;

  if not found then
    raise exception 'Partie introuvable';
  end if;

  if v_status != 'playing' then
    raise exception 'Cette partie est deja terminee';
  end if;

  -- Verifier que l'appelant est bien un des joueurs
  if auth.uid() != v_player1 and auth.uid() != v_player2 then
    raise exception 'Vous n''etes pas un joueur de cette partie';
  end if;

  -- Rembourser les deux joueurs
  update public.user_profiles
  set coins = coins + v_bet, updated_at = now()
  where id = v_player1;

  update public.user_profiles
  set coins = coins + v_bet, updated_at = now()
  where id = v_player2;

  -- Marquer la partie comme annulee (pas de gagnant)
  update public.ludo_games
  set status = 'cancelled', winner_id = null, updated_at = now()
  where id = p_game_id;

  -- Mettre a jour la salle associee si elle existe
  update public.ludo_rooms
  set status = 'cancelled', updated_at = now()
  where game_id = p_game_id;
end;
$$ language plpgsql security definer;
