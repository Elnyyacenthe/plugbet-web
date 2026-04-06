-- ============================================================
-- LUDO MULTIPLAYER MODULE - Supabase Setup
-- Exécuter ce script dans Supabase SQL Editor
-- ============================================================

-- 1. Table des profils utilisateurs avec coins
create table if not exists public.user_profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  username text not null default '',
  coins int not null default 500,
  games_played int not null default 0,
  games_won int not null default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.user_profiles enable row level security;

create policy "Users can read all profiles"
  on public.user_profiles for select using (true);

create policy "Users can update own profile"
  on public.user_profiles for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.user_profiles for insert with check (auth.uid() = id);

-- Trigger pour créer un profil automatiquement à l'inscription
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.user_profiles (id, username, coins)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'Player_' || left(new.id::text, 6)),
    500
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Table des défis Ludo
create table if not exists public.ludo_challenges (
  id uuid default gen_random_uuid() primary key,
  from_user uuid references auth.users(id) on delete cascade not null,
  to_user uuid references auth.users(id) on delete cascade not null,
  bet_amount int not null default 0,
  status text not null default 'pending',
  game_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.ludo_challenges enable row level security;

create policy "Users can read their challenges"
  on public.ludo_challenges for select
  using (auth.uid() = from_user or auth.uid() = to_user);

create policy "Users can create challenges"
  on public.ludo_challenges for insert
  with check (auth.uid() = from_user);

create policy "Users can update their challenges"
  on public.ludo_challenges for update
  using (auth.uid() = from_user or auth.uid() = to_user);

-- Activer Realtime sur les challenges
alter publication supabase_realtime add table public.ludo_challenges;

-- 3. Table des parties Ludo
create table if not exists public.ludo_games (
  id uuid default gen_random_uuid() primary key,
  challenge_id uuid references public.ludo_challenges(id),
  player1 uuid references auth.users(id) not null,
  player2 uuid references auth.users(id) not null,
  current_turn uuid references auth.users(id) not null,
  bet_amount int not null default 0,
  game_state jsonb not null default '{}'::jsonb,
  status text not null default 'playing',
  winner_id uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.ludo_games enable row level security;

create policy "Players can read their games"
  on public.ludo_games for select
  using (auth.uid() = player1 or auth.uid() = player2);

create policy "Players can update their games"
  on public.ludo_games for update
  using (auth.uid() = player1 or auth.uid() = player2);

create policy "System can insert games"
  on public.ludo_games for insert
  with check (true);

-- Activer Realtime sur les games
alter publication supabase_realtime add table public.ludo_games;

-- 4. Table de présence en ligne (lobby)
create table if not exists public.ludo_online (
  user_id uuid references auth.users(id) on delete cascade primary key,
  username text not null,
  coins int not null default 500,
  last_seen timestamptz default now()
);

alter table public.ludo_online enable row level security;

create policy "Anyone can read online users"
  on public.ludo_online for select using (true);

create policy "Users can manage own presence"
  on public.ludo_online for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter publication supabase_realtime add table public.ludo_online;

-- ============================================================
-- 5. Fonctions sécurisées pour la gestion des coins
-- ============================================================

-- Fonction : Accepter un défi (débiter les deux joueurs, créer la partie)
create or replace function public.accept_challenge(p_challenge_id uuid)
returns uuid as $$
declare
  v_from_user uuid;
  v_to_user uuid;
  v_bet int;
  v_game_id uuid;
  v_from_coins int;
  v_to_coins int;
begin
  -- Vérifier que c'est bien le destinataire qui accepte
  select from_user, to_user, bet_amount
  into v_from_user, v_to_user, v_bet
  from public.ludo_challenges
  where id = p_challenge_id and status = 'pending';

  if not found then
    raise exception 'Défi introuvable ou déjà traité';
  end if;

  if v_to_user != auth.uid() then
    raise exception 'Seul le destinataire peut accepter ce défi';
  end if;

  -- Vérifier les soldes
  select coins into v_from_coins from public.user_profiles where id = v_from_user;
  select coins into v_to_coins from public.user_profiles where id = v_to_user;

  if v_from_coins < v_bet then
    raise exception 'Le challenger n''a pas assez de coins';
  end if;

  if v_to_coins < v_bet then
    raise exception 'Vous n''avez pas assez de coins';
  end if;

  -- Débiter les deux joueurs
  update public.user_profiles set coins = coins - v_bet, updated_at = now() where id = v_from_user;
  update public.user_profiles set coins = coins - v_bet, updated_at = now() where id = v_to_user;

  -- Créer la partie
  insert into public.ludo_games (
    challenge_id, player1, player2, current_turn, bet_amount,
    game_state, status
  )
  values (
    p_challenge_id, v_from_user, v_to_user, v_from_user, v_bet,
    jsonb_build_object(
      'pawns', jsonb_build_object(
        v_from_user::text, '[0,0,0,0]'::jsonb,
        v_to_user::text, '[0,0,0,0]'::jsonb
      ),
      'lastDice', 0,
      'hasRolled', false,
      'moveHistory', '[]'::jsonb
    ),
    'playing'
  )
  returning id into v_game_id;

  -- Mettre à jour le challenge
  update public.ludo_challenges
  set status = 'accepted', game_id = v_game_id, updated_at = now()
  where id = p_challenge_id;

  return v_game_id;
end;
$$ language plpgsql security definer;

-- Fonction : Terminer une partie (créditer le gagnant)
create or replace function public.finish_ludo_game(p_game_id uuid, p_winner_id uuid)
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
    raise exception 'Cette partie est déjà terminée';
  end if;

  -- Vérifier que le gagnant est bien un des joueurs
  if p_winner_id != v_player1 and p_winner_id != v_player2 then
    raise exception 'Le gagnant doit être un des joueurs';
  end if;

  -- Créditer le gagnant (pot = bet * 2)
  update public.user_profiles
  set coins = coins + (v_bet * 2),
      games_won = games_won + 1,
      games_played = games_played + 1,
      updated_at = now()
  where id = p_winner_id;

  -- Incrémenter games_played du perdant
  update public.user_profiles
  set games_played = games_played + 1,
      updated_at = now()
  where id in (v_player1, v_player2)
    and id != p_winner_id;

  -- Marquer la partie comme terminée
  update public.ludo_games
  set status = 'finished', winner_id = p_winner_id, updated_at = now()
  where id = p_game_id;
end;
$$ language plpgsql security definer;

-- Fonction : Abandonner une partie (l'adversaire gagne)
create or replace function public.abandon_ludo_game(p_game_id uuid)
returns void as $$
declare
  v_player1 uuid;
  v_player2 uuid;
  v_winner uuid;
begin
  select player1, player2 into v_player1, v_player2
  from public.ludo_games where id = p_game_id and status = 'playing';

  if not found then
    raise exception 'Partie introuvable ou déjà terminée';
  end if;

  -- Le gagnant est l'autre joueur
  if auth.uid() = v_player1 then
    v_winner := v_player2;
  elsif auth.uid() = v_player2 then
    v_winner := v_player1;
  else
    raise exception 'Vous n''êtes pas un joueur de cette partie';
  end if;

  perform public.finish_ludo_game(p_game_id, v_winner);
end;
$$ language plpgsql security definer;

-- ============================================================
-- 6. Index pour les performances
-- ============================================================
create index if not exists idx_challenges_to_user on public.ludo_challenges(to_user) where status = 'pending';
create index if not exists idx_challenges_from_user on public.ludo_challenges(from_user);
create index if not exists idx_games_players on public.ludo_games(player1, player2);
create index if not exists idx_games_status on public.ludo_games(status) where status = 'playing';
create index if not exists idx_online_last_seen on public.ludo_online(last_seen);
