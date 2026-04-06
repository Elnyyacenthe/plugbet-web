-- ============================================================
-- AVIATOR – Supabase SQL (idempotent)
-- Tables : aviator_rounds · aviator_chat
-- ============================================================

-- ─── 1. TABLE aviator_rounds ──────────────────────────────
-- Historique public des rounds (crash points + seeds provably fair)
CREATE TABLE IF NOT EXISTS public.aviator_rounds (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id     TEXT NOT NULL UNIQUE,
  crash_point  DOUBLE PRECISION NOT NULL,
  server_seed  TEXT NOT NULL,
  client_seed  TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.aviator_rounds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "aviator_rounds_select" ON public.aviator_rounds;
CREATE POLICY "aviator_rounds_select" ON public.aviator_rounds
  FOR SELECT USING (true);  -- historique visible par tous

DROP POLICY IF EXISTS "aviator_rounds_insert" ON public.aviator_rounds;
CREATE POLICY "aviator_rounds_insert" ON public.aviator_rounds
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ─── 2. TABLE aviator_chat ────────────────────────────────
-- Messages de chat live (cash outs + messages joueurs)
CREATE TABLE IF NOT EXISTS public.aviator_chat (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username   TEXT NOT NULL DEFAULT 'Joueur',
  text       TEXT NOT NULL,
  is_system  BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.aviator_chat ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "aviator_chat_select" ON public.aviator_chat;
CREATE POLICY "aviator_chat_select" ON public.aviator_chat
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "aviator_chat_insert" ON public.aviator_chat;
CREATE POLICY "aviator_chat_insert" ON public.aviator_chat
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Garder seulement les 500 derniers messages (nettoyage auto)
CREATE OR REPLACE FUNCTION public.aviator_trim_chat()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.aviator_chat
  WHERE id IN (
    SELECT id FROM public.aviator_chat
    ORDER BY created_at DESC
    OFFSET 500
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_aviator_trim_chat ON public.aviator_chat;
CREATE TRIGGER trg_aviator_trim_chat
  AFTER INSERT ON public.aviator_chat
  FOR EACH STATEMENT EXECUTE FUNCTION public.aviator_trim_chat();

-- ─── 3. Realtime ──────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'aviator_rounds'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.aviator_rounds;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'aviator_chat'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.aviator_chat;
  END IF;
END $$;

-- ─── Vérification ─────────────────────────────────────────
-- Tables  : aviator_rounds · aviator_chat
-- Trigger : trg_aviator_trim_chat (nettoyage auto chat >500 msgs)
-- Realtime: activé sur les deux tables
