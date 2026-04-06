-- ============================================================
-- FANTASY MODULE – Supabase SQL
-- À exécuter dans : Supabase > SQL Editor > New Query
-- Script idempotent : peut être relancé sans erreur
-- ============================================================

-- ─── 1. TABLE fantasy_teams ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.fantasy_teams (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  team_name       TEXT NOT NULL DEFAULT 'Mon Équipe',
  budget          INT  NOT NULL DEFAULT 10000,
  total_value     INT  NOT NULL DEFAULT 10000,
  total_points    INT  NOT NULL DEFAULT 0,
  gameweek_points INT  NOT NULL DEFAULT 0,
  free_transfers  INT  NOT NULL DEFAULT 1,
  gw_transfers    INT  NOT NULL DEFAULT 0,
  chips_used      TEXT[] NOT NULL DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

-- Nouvelles colonnes (si table existait déjà sans elles)
ALTER TABLE public.fantasy_teams
  ADD COLUMN IF NOT EXISTS free_transfers INT NOT NULL DEFAULT 1;
ALTER TABLE public.fantasy_teams
  ADD COLUMN IF NOT EXISTS gw_transfers INT NOT NULL DEFAULT 0;
ALTER TABLE public.fantasy_teams
  ADD COLUMN IF NOT EXISTS chips_used TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE public.fantasy_teams
  ADD COLUMN IF NOT EXISTS formation TEXT NOT NULL DEFAULT '4-4-2';
ALTER TABLE public.fantasy_teams
  ADD COLUMN IF NOT EXISTS tactics JSONB NOT NULL DEFAULT '{"play_style":"balanced","mentality":"balanced","pressing":"medium","tempo":"normal","width":"normal"}';

ALTER TABLE public.fantasy_teams ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fantasy_teams_select" ON public.fantasy_teams;
CREATE POLICY "fantasy_teams_select" ON public.fantasy_teams
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_teams_insert" ON public.fantasy_teams;
CREATE POLICY "fantasy_teams_insert" ON public.fantasy_teams
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_teams_update" ON public.fantasy_teams;
CREATE POLICY "fantasy_teams_update" ON public.fantasy_teams
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_teams_delete" ON public.fantasy_teams;
CREATE POLICY "fantasy_teams_delete" ON public.fantasy_teams
  FOR DELETE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_fantasy_teams_updated ON public.fantasy_teams;
CREATE TRIGGER trg_fantasy_teams_updated
  BEFORE UPDATE ON public.fantasy_teams
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── 2. TABLE fantasy_picks ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.fantasy_picks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id         UUID NOT NULL REFERENCES public.fantasy_teams(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  element_id      INT  NOT NULL,
  position        INT  NOT NULL,
  is_captain      BOOLEAN NOT NULL DEFAULT false,
  is_vice_captain BOOLEAN NOT NULL DEFAULT false,
  is_starter      BOOLEAN NOT NULL DEFAULT true,
  club_team_id    INT  NOT NULL DEFAULT 0,
  purchase_price  INT  NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(team_id, element_id)
);

-- Nouvelles colonnes (si table existait déjà sans elles)
ALTER TABLE public.fantasy_picks
  ADD COLUMN IF NOT EXISTS is_starter BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.fantasy_picks
  ADD COLUMN IF NOT EXISTS club_team_id INT NOT NULL DEFAULT 0;
ALTER TABLE public.fantasy_picks
  ADD COLUMN IF NOT EXISTS bench_order INT NOT NULL DEFAULT 99;

ALTER TABLE public.fantasy_picks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fantasy_picks_select" ON public.fantasy_picks;
CREATE POLICY "fantasy_picks_select" ON public.fantasy_picks
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_picks_insert" ON public.fantasy_picks;
CREATE POLICY "fantasy_picks_insert" ON public.fantasy_picks
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_picks_update" ON public.fantasy_picks;
CREATE POLICY "fantasy_picks_update" ON public.fantasy_picks
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_picks_delete" ON public.fantasy_picks;
CREATE POLICY "fantasy_picks_delete" ON public.fantasy_picks
  FOR DELETE USING (auth.uid() = user_id);

-- ─── 3. TABLE fantasy_leagues ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.fantasy_leagues (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  creator_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_private   BOOLEAN NOT NULL DEFAULT false,
  private_code TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(private_code)
);

ALTER TABLE public.fantasy_leagues ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fantasy_leagues_select" ON public.fantasy_leagues;
CREATE POLICY "fantasy_leagues_select" ON public.fantasy_leagues
  FOR SELECT USING (NOT is_private OR creator_id = auth.uid());

DROP POLICY IF EXISTS "fantasy_leagues_insert" ON public.fantasy_leagues;
CREATE POLICY "fantasy_leagues_insert" ON public.fantasy_leagues
  FOR INSERT WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "fantasy_leagues_update" ON public.fantasy_leagues;
CREATE POLICY "fantasy_leagues_update" ON public.fantasy_leagues
  FOR UPDATE USING (auth.uid() = creator_id);

DROP POLICY IF EXISTS "fantasy_leagues_delete" ON public.fantasy_leagues;
CREATE POLICY "fantasy_leagues_delete" ON public.fantasy_leagues
  FOR DELETE USING (auth.uid() = creator_id);

-- ─── 4. TABLE fantasy_league_members ─────────────────────
CREATE TABLE IF NOT EXISTS public.fantasy_league_members (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id    UUID NOT NULL REFERENCES public.fantasy_leagues(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  team_name    TEXT NOT NULL DEFAULT 'Mon Équipe',
  total_points INT  NOT NULL DEFAULT 0,
  joined_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(league_id, user_id)
);

ALTER TABLE public.fantasy_league_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fantasy_members_select" ON public.fantasy_league_members;
CREATE POLICY "fantasy_members_select" ON public.fantasy_league_members
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "fantasy_members_insert" ON public.fantasy_league_members;
CREATE POLICY "fantasy_members_insert" ON public.fantasy_league_members
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_members_update" ON public.fantasy_league_members;
CREATE POLICY "fantasy_members_update" ON public.fantasy_league_members
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "fantasy_members_delete" ON public.fantasy_league_members;
CREATE POLICY "fantasy_members_delete" ON public.fantasy_league_members
  FOR DELETE USING (auth.uid() = user_id);

-- ─── 5. RPC : fantasy_spend_budget ───────────────────────
CREATE OR REPLACE FUNCTION public.fantasy_spend_budget(
  p_team_id UUID,
  p_amount  INT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_budget INT;
  v_owner  UUID;
BEGIN
  SELECT budget, user_id INTO v_budget, v_owner
  FROM public.fantasy_teams WHERE id = p_team_id;

  IF v_owner IS NULL THEN RAISE EXCEPTION 'TEAM_NOT_FOUND'; END IF;
  IF v_owner <> auth.uid() THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF (v_budget - p_amount) < 0 THEN
    RAISE EXCEPTION 'BUDGET_INSUFFISANT: budget=%, cout=%', v_budget, p_amount;
  END IF;

  UPDATE public.fantasy_teams SET budget = budget - p_amount WHERE id = p_team_id;
END;
$$;

-- ─── 6. RPC : fantasy_add_points ─────────────────────────
CREATE OR REPLACE FUNCTION public.fantasy_add_points(
  p_team_id UUID,
  p_points  INT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_owner     UUID;
  v_new_total INT;
  v_team_name TEXT;
BEGIN
  SELECT user_id, total_points + p_points, team_name
  INTO v_owner, v_new_total, v_team_name
  FROM public.fantasy_teams WHERE id = p_team_id;

  IF v_owner IS NULL THEN RAISE EXCEPTION 'TEAM_NOT_FOUND'; END IF;

  UPDATE public.fantasy_teams SET total_points = v_new_total WHERE id = p_team_id;

  UPDATE public.fantasy_league_members
  SET total_points = v_new_total, team_name = v_team_name
  WHERE user_id = v_owner;
END;
$$;

-- ─── 7. RPC : fantasy_increment_gw_transfers ─────────────
CREATE OR REPLACE FUNCTION public.fantasy_increment_gw_transfers(
  p_team_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_owner UUID;
BEGIN
  SELECT user_id INTO v_owner FROM public.fantasy_teams WHERE id = p_team_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'TEAM_NOT_FOUND'; END IF;
  IF v_owner <> auth.uid() THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;

  UPDATE public.fantasy_teams SET gw_transfers = gw_transfers + 1 WHERE id = p_team_id;
END;
$$;

-- ─── 8. RPC : fantasy_use_chip ────────────────────────────
CREATE OR REPLACE FUNCTION public.fantasy_use_chip(
  p_team_id   UUID,
  p_chip_name TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_owner UUID;
  v_chips TEXT[];
BEGIN
  SELECT user_id, chips_used INTO v_owner, v_chips
  FROM public.fantasy_teams WHERE id = p_team_id;

  IF v_owner IS NULL THEN RAISE EXCEPTION 'TEAM_NOT_FOUND'; END IF;
  IF v_owner <> auth.uid() THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;
  IF p_chip_name = ANY(v_chips) THEN
    RAISE EXCEPTION 'CHIP_ALREADY_USED: %', p_chip_name;
  END IF;

  UPDATE public.fantasy_teams
  SET chips_used = array_append(chips_used, p_chip_name)
  WHERE id = p_team_id;
END;
$$;

-- ─── 9. RPC : fantasy_reset_gw_transfers ─────────────────
CREATE OR REPLACE FUNCTION public.fantasy_reset_gw_transfers(
  p_team_id UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.fantasy_teams
  SET gw_transfers   = 0,
      free_transfers = LEAST(free_transfers + 1, 2)
  WHERE id = p_team_id;
END;
$$;

-- ─── 10. Realtime ─────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'fantasy_teams'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.fantasy_teams;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'fantasy_picks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.fantasy_picks;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'fantasy_league_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.fantasy_league_members;
  END IF;
END $$;

-- ─── Vérification ─────────────────────────────────────────
-- Tables :  fantasy_teams · fantasy_picks · fantasy_leagues · fantasy_league_members
-- RPCs   :  fantasy_spend_budget · fantasy_add_points
--           fantasy_increment_gw_transfers · fantasy_use_chip · fantasy_reset_gw_transfers
