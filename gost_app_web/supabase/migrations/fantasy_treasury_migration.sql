-- ============================================================
-- FANTASY - Migration vers le treasury unifie
-- ============================================================
-- A executer APRES treasury_unified.sql + treasury_final_fix.sql.
-- Idempotent : safe to re-run.
--
-- Cree (les fonctions n'existaient pas dans la DB) :
--   1. ALTER fantasy_leagues : ajoute entry_fee, pot, status, winner_id,
--                              prize_distribution, finished_at, league_type
--   2. fantasy_join_league_with_fee : debit entry_fee via treasury_place_bet
--   3. fantasy_finish_league : distribue le pot au top N selon
--                              prize_distribution, via apply_game_payout
--                              (10% commission UNIFORME sur chaque gain)
--
-- Logique payout :
--   - Pot total = entry_fee * nb_joueurs (collecte a chaque join)
--   - prize_distribution = jsonb array de pourcentages : [60, 30, 10]
--     -> top1 recoit 60% du pot (gain BRUT), top2 30%, top3 10%
--   - apply_game_payout splitte chaque gain : 90% winner, 10% caisse
--   - Exemple : pot 100000, top1 60000 -> 54000 winner, 6000 caisse
--   - Total commission casino = 10% du pot total (sur la part distribuee)
-- ============================================================

-- ============================================================
-- 0) ALTER TABLE fantasy_leagues - colonnes manquantes
-- ============================================================
alter table public.fantasy_leagues
  add column if not exists entry_fee int not null default 0,
  add column if not exists pot int not null default 0,
  add column if not exists status text not null default 'open',
  add column if not exists winner_id uuid references public.user_profiles(id),
  add column if not exists prize_distribution jsonb not null default '[60, 30, 10]'::jsonb,
  add column if not exists finished_at timestamptz,
  add column if not exists end_date timestamptz,
  add column if not exists league_type text not null default 'classic',
  add column if not exists max_players int not null default 50,
  add column if not exists description text;

-- Index pour recherche rapide par status
create index if not exists fantasy_leagues_status_idx
  on public.fantasy_leagues(status);

-- ============================================================
-- 1) fantasy_join_league_with_fee - debit entry fee via treasury
-- ============================================================
create or replace function public.fantasy_join_league_with_fee(
  p_league_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_league record;
  v_member_count int;
  v_team_name text;
  v_username text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  end if;

  -- Lock la ligue pour update concurrentiel propre du pot
  select * into v_league from public.fantasy_leagues
    where id = p_league_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'LEAGUE_NOT_FOUND');
  end if;

  if v_league.status != 'open' then
    return jsonb_build_object('success', false, 'error', 'LEAGUE_CLOSED');
  end if;

  -- Deja membre ?
  if exists (select 1 from public.fantasy_league_members
             where league_id = p_league_id and user_id = v_uid) then
    return jsonb_build_object('success', false, 'error', 'deja membre');
  end if;

  -- Capacite max
  select count(*) into v_member_count
    from public.fantasy_league_members where league_id = p_league_id;
  if v_member_count >= v_league.max_players then
    return jsonb_build_object('success', false, 'error', 'LEAGUE_FULL');
  end if;

  -- ===== TREASURY MIGRATION =====
  -- Si entry_fee > 0, debit via la caisse (atomique, verifie solde, log auto)
  if v_league.entry_fee > 0 then
    begin
      perform public.treasury_place_bet(
        'fantasy', p_league_id::text, v_uid, v_league.entry_fee
      );
    exception
      when others then
        -- treasury_place_bet leve 'INSUFFICIENT_COINS' en cas de solde insuffisant.
        -- Le code Flutter detecte le message FR "Solde insuffisant" pour mapper
        -- vers FantasyError.budgetInsuffisant. On traduit donc ici.
        if SQLERRM like '%INSUFFICIENT_COINS%' then
          return jsonb_build_object('success', false, 'error', 'Solde insuffisant');
        end if;
        return jsonb_build_object('success', false, 'error', SQLERRM);
    end;

    -- Cumuler dans le pot
    update public.fantasy_leagues
      set pot = pot + v_league.entry_fee
      where id = p_league_id;
  end if;

  -- Recuperer team_name pour cohesion avec l'affichage
  select coalesce(team_name, 'Mon Equipe') into v_team_name
    from public.fantasy_teams where user_id = v_uid limit 1;
  if v_team_name is null then
    select coalesce(username, 'Joueur') into v_username
      from public.user_profiles where id = v_uid;
    v_team_name := coalesce(v_username, 'Joueur');
  end if;

  insert into public.fantasy_league_members(league_id, user_id, team_name)
    values (p_league_id, v_uid, v_team_name);

  return jsonb_build_object(
    'success', true,
    'league_id', p_league_id,
    'entry_fee', v_league.entry_fee,
    'pot', v_league.pot + v_league.entry_fee
  );
end;
$function$;

grant execute on function public.fantasy_join_league_with_fee(uuid) to authenticated;

-- ============================================================
-- 2) fantasy_finish_league - distribution pot via treasury
-- ============================================================
-- Distribue le pot au top N selon prize_distribution.
-- p_winner_id (optionnel) : override le top1 (sinon ranking auto par points).
-- Top 2..N : auto par total_points DESC en excluant le top1.
--
-- Seul le createur de la ligue peut clore.
create or replace function public.fantasy_finish_league(
  p_league_id uuid,
  p_winner_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_league record;
  v_dist jsonb;
  v_dist_len int;
  v_pot int;
  v_total_pct int := 0;
  v_pct int;
  v_pos int;
  v_winner_uid uuid;
  v_gross int;
  v_winners jsonb := '[]'::jsonb;
  v_excluded uuid[] := '{}';
  v_member record;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  end if;

  select * into v_league from public.fantasy_leagues
    where id = p_league_id for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'LEAGUE_NOT_FOUND');
  end if;

  if v_league.creator_id != v_uid then
    return jsonb_build_object('success', false, 'error', 'NOT_CREATOR');
  end if;

  if v_league.status != 'open' then
    return jsonb_build_object('success', false, 'error', 'ALREADY_FINISHED');
  end if;

  -- Date de fin obligatoire et atteinte
  if v_league.end_date is null then
    return jsonb_build_object('success', false, 'error', 'NO_END_DATE');
  end if;
  if now() < v_league.end_date then
    return jsonb_build_object('success', false,
      'error', format('NOT_YET_CLOSEABLE: ends at %s', v_league.end_date));
  end if;

  v_dist := v_league.prize_distribution;
  v_pot := v_league.pot;
  v_dist_len := jsonb_array_length(v_dist);

  -- Sanity check : somme des pourcentages = 100
  for i in 0..v_dist_len - 1 loop
    v_total_pct := v_total_pct + (v_dist ->> i)::int;
  end loop;
  if v_total_pct != 100 then
    return jsonb_build_object('success', false,
      'error', format('PRIZE_DIST_INVALID: sum=%s, expected 100', v_total_pct));
  end if;

  -- Distribuer chaque position
  for v_pos in 0..v_dist_len - 1 loop
    v_pct := (v_dist ->> v_pos)::int;
    v_gross := floor(v_pot * v_pct / 100.0)::int;
    v_winner_uid := null;

    if v_pos = 0 and p_winner_id is not null then
      -- Override explicite du top1
      v_winner_uid := p_winner_id;
    else
      -- Auto-ranking par points DESC, en excluant les positions deja attribuees
      select user_id into v_winner_uid
        from public.fantasy_league_members
        where league_id = p_league_id
          and (cardinality(v_excluded) = 0 or user_id != all(v_excluded))
        order by total_points desc, joined_at asc
        limit 1;
    end if;

    if v_winner_uid is null then
      -- Pas assez de joueurs pour cette position : on arrete
      exit;
    end if;

    v_excluded := array_append(v_excluded, v_winner_uid);

    -- ===== TREASURY MIGRATION =====
    -- apply_game_payout : splitte 90% winner, 10% caisse, log auto
    if v_gross > 0 then
      perform public.apply_game_payout(
        'fantasy', p_league_id::text, v_winner_uid, v_gross
      );
    end if;

    v_winners := v_winners || jsonb_build_object(
      'position', v_pos + 1,
      'user_id', v_winner_uid,
      'pct', v_pct,
      'gross', v_gross,
      'net', floor(v_gross * 0.90)::int
    );
  end loop;

  -- Update league : finished
  update public.fantasy_leagues
    set status = 'finished',
        winner_id = (v_winners -> 0 ->> 'user_id')::uuid,
        finished_at = now()
    where id = p_league_id;

  return jsonb_build_object(
    'success', true,
    'league_id', p_league_id,
    'pot', v_pot,
    'winners', v_winners
  );
end;
$function$;

grant execute on function public.fantasy_finish_league(uuid, uuid) to authenticated;

-- ============================================================
-- FIN
-- ============================================================
-- Verifications post-execution :
--
-- Scenario 1 (10 joueurs, entry 10000, top1 60% / top2 30% / top3 10%) :
--   - 10 x fantasy_join_league_with_fee : caisse +10000 chacun = +100000
--   - Pot = 100000
--   - fantasy_finish_league (creator):
--     - top1: gross 60000 -> apply_game_payout -> winner +54000, caisse +6000
--     - top2: gross 30000 -> winner +27000, caisse +3000
--     - top3: gross 10000 -> winner +9000, caisse +1000
--     - Total verses joueurs = 90000
--     - Total caisse round = +100000 - 90000 = +10000 (= 10% commission)
--   - Bilan systeme = 0 (zero creation)
--
-- Scenario 2 (5 joueurs, distribution [70, 30]) :
--   - Pot 50000, top1 70% = 35000 -> winner 31500, caisse 3500
--   - top2 30% = 15000 -> winner 13500, caisse 1500
--   - Caisse round = 50000 - 45000 = 5000 (= 10%)
--
-- API Flutter (existing) :
--   - joinLeague(leagueId) -> fantasy_join_league_with_fee(p_league_id)
--     return { success, error?, league_id, entry_fee, pot }
--     "Solde insuffisant" est detecte par contains() cote client
--   - finishLeague(leagueId, winnerId) -> fantasy_finish_league(p_league_id, p_winner_id)
--     return { success, league_id, pot, winners: [{position, user_id, pct, gross, net}] }
--
-- Notes :
-- - prize_distribution est CONFIGURABLE par ligue (jsonb sur fantasy_leagues).
--   Defaut [60, 30, 10]. Le createur peut modifier avant clture en updatant
--   la colonne directement (pas de RPC dedie pour l'instant).
-- - p_winner_id sert d'override pour le top1 (si choix manuel par creator).
--   top2..N sont toujours auto-determines par total_points DESC.
-- - Le pot est cumule lazy a chaque join (atomic via FOR UPDATE).
--   Les join concurrents sont serialisés.
