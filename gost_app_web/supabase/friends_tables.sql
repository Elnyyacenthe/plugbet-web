-- ============================================================
-- AMIS – Tables friend_requests + friendships (idempotent)
-- ============================================================

-- ── 1. Demandes d'amitié ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.friend_requests (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  from_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  to_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  from_username TEXT DEFAULT 'Joueur',
  from_xp    INT DEFAULT 0,
  status     TEXT DEFAULT 'pending',  -- 'pending' | 'accepted' | 'declined'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(from_id, to_id)
);

-- ── 2. Relations d'amitié (bidirectionnelles) ─────────────
CREATE TABLE IF NOT EXISTS public.friendships (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  friend_id  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  status     TEXT DEFAULT 'accepted',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, friend_id)
);

-- ── 3. RLS ───────────────────────────────────────────────
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- friend_requests : visible par l'expéditeur et le destinataire
DROP POLICY IF EXISTS "friend_requests_select" ON public.friend_requests;
CREATE POLICY "friend_requests_select" ON public.friend_requests
  FOR SELECT USING (auth.uid() = from_id OR auth.uid() = to_id);

DROP POLICY IF EXISTS "friend_requests_insert" ON public.friend_requests;
CREATE POLICY "friend_requests_insert" ON public.friend_requests
  FOR INSERT WITH CHECK (auth.uid() = from_id);

DROP POLICY IF EXISTS "friend_requests_update" ON public.friend_requests;
CREATE POLICY "friend_requests_update" ON public.friend_requests
  FOR UPDATE USING (auth.uid() = to_id);

DROP POLICY IF EXISTS "friend_requests_delete" ON public.friend_requests;
CREATE POLICY "friend_requests_delete" ON public.friend_requests
  FOR DELETE USING (auth.uid() = from_id OR auth.uid() = to_id);

-- friendships : visible par les deux amis
DROP POLICY IF EXISTS "friendships_select" ON public.friendships;
CREATE POLICY "friendships_select" ON public.friendships
  FOR SELECT USING (auth.uid() = user_id OR auth.uid() = friend_id);

DROP POLICY IF EXISTS "friendships_insert" ON public.friendships;
CREATE POLICY "friendships_insert" ON public.friendships
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "friendships_delete" ON public.friendships;
CREATE POLICY "friendships_delete" ON public.friendships
  FOR DELETE USING (auth.uid() = user_id OR auth.uid() = friend_id);

-- ── 4. Realtime ──────────────────────────────────────────
DO $rt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'friend_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_requests;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'friendships'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.friendships;
  END IF;
END $rt$;
