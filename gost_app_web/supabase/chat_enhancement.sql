-- ============================================================
-- CHAT ENHANCEMENT – WhatsApp-like features (idempotent)
-- ============================================================

-- ── 1. Nouvelles colonnes sur private_messages ────────────
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS message_type TEXT DEFAULT 'text';
-- 'text' | 'image' | 'voice' | 'system'
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS media_url TEXT;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS media_duration INT; -- durée voix en secondes
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.private_messages(id) ON DELETE SET NULL;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;
ALTER TABLE public.private_messages ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

-- ── 2. Réactions aux messages ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.message_reactions (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID REFERENCES public.private_messages(id) ON DELETE CASCADE NOT NULL,
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  emoji      TEXT NOT NULL,  -- '👍' '❤️' '😂' '😮' '😢' '🔥'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(message_id, user_id)  -- un seul emoji par user par message
);

-- ── 3. Statut en ligne / dernière connexion ───────────────
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ DEFAULT NOW();

-- ── 4. Indicateur de frappe (typing) ──────────────────────
CREATE TABLE IF NOT EXISTS public.typing_indicators (
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  is_typing       BOOLEAN DEFAULT false,
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, conversation_id)
);

-- ── 5. Tokens push notification ───────────────────────────
CREATE TABLE IF NOT EXISTS public.push_tokens (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token      TEXT NOT NULL,
  platform   TEXT DEFAULT 'android',  -- 'android' | 'ios' | 'web'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, token)
);

-- ── 6. Conversations : ajout champs utiles ────────────────
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS is_pinned_user1 BOOLEAN DEFAULT false;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS is_pinned_user2 BOOLEAN DEFAULT false;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS is_muted_user1 BOOLEAN DEFAULT false;
ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS is_muted_user2 BOOLEAN DEFAULT false;

-- ── 7. RLS ───────────────────────────────────────────────
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

-- message_reactions : accessible si on participe à la conversation
DROP POLICY IF EXISTS "reactions_select" ON public.message_reactions;
CREATE POLICY "reactions_select" ON public.message_reactions
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "reactions_insert" ON public.message_reactions;
CREATE POLICY "reactions_insert" ON public.message_reactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reactions_delete" ON public.message_reactions;
CREATE POLICY "reactions_delete" ON public.message_reactions
  FOR DELETE USING (auth.uid() = user_id);

-- typing_indicators : accessible par les participants
DROP POLICY IF EXISTS "typing_select" ON public.typing_indicators;
CREATE POLICY "typing_select" ON public.typing_indicators
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "typing_upsert" ON public.typing_indicators;
CREATE POLICY "typing_upsert" ON public.typing_indicators
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "typing_update" ON public.typing_indicators;
CREATE POLICY "typing_update" ON public.typing_indicators
  FOR UPDATE USING (auth.uid() = user_id);

-- push_tokens : chacun gère ses propres tokens
DROP POLICY IF EXISTS "push_tokens_select" ON public.push_tokens;
CREATE POLICY "push_tokens_select" ON public.push_tokens
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "push_tokens_insert" ON public.push_tokens;
CREATE POLICY "push_tokens_insert" ON public.push_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "push_tokens_delete" ON public.push_tokens;
CREATE POLICY "push_tokens_delete" ON public.push_tokens
  FOR DELETE USING (auth.uid() = user_id);

-- ── 8. Realtime ──────────────────────────────────────────
DO $rt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'message_reactions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'typing_indicators'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;
  END IF;
END $rt$;

-- ── 9. Fonction pour mettre à jour last_seen ─────────────
CREATE OR REPLACE FUNCTION public.update_user_presence(p_online BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.user_profiles
  SET is_online = p_online,
      last_seen_at = NOW()
  WHERE id = auth.uid();
END;
$$;
