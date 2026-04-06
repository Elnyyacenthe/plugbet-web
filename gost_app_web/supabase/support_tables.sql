-- ============================================================
-- SERVICE CLIENT – Tables support (idempotent)
-- ============================================================

-- ── 1. Tickets de support ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  username      TEXT DEFAULT '',
  subject       TEXT NOT NULL,
  category      TEXT DEFAULT 'general',  -- 'general' | 'paiement' | 'compte' | 'jeu' | 'bug'
  status        TEXT DEFAULT 'open',     -- 'open' | 'answered' | 'closed'
  unread_user   BOOLEAN DEFAULT FALSE,   -- admin a répondu, user pas encore lu
  unread_admin  BOOLEAN DEFAULT TRUE,    -- nouveau message user non lu par admin
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. Messages du ticket ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.support_messages (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_id  UUID REFERENCES public.support_tickets(id) ON DELETE CASCADE NOT NULL,
  sender_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_admin   BOOLEAN DEFAULT FALSE,
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. RLS ───────────────────────────────────────────────
ALTER TABLE public.support_tickets   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages  ENABLE ROW LEVEL SECURITY;

-- Tickets : le propriétaire voit les siens, les admins voient tout
DROP POLICY IF EXISTS "support_tickets_select" ON public.support_tickets;
CREATE POLICY "support_tickets_select" ON public.support_tickets
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "support_tickets_insert" ON public.support_tickets;
CREATE POLICY "support_tickets_insert" ON public.support_tickets
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "support_tickets_update_owner" ON public.support_tickets;
CREATE POLICY "support_tickets_update_owner" ON public.support_tickets
  FOR UPDATE USING (auth.uid() = user_id);

-- Messages : accessibles si on possède le ticket
DROP POLICY IF EXISTS "support_messages_select" ON public.support_messages;
CREATE POLICY "support_messages_select" ON public.support_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
    OR is_admin = FALSE  -- les messages user sont lisibles par tous les owners du ticket
  );

DROP POLICY IF EXISTS "support_messages_insert" ON public.support_messages;
CREATE POLICY "support_messages_insert" ON public.support_messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
    AND is_admin = FALSE
  );

-- ── 4. Trigger : updated_at auto ─────────────────────────
CREATE OR REPLACE FUNCTION public.support_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_ticket_updated ON public.support_tickets;
CREATE TRIGGER trg_support_ticket_updated
  BEFORE UPDATE ON public.support_tickets
  FOR EACH ROW EXECUTE FUNCTION public.support_set_updated_at();

-- Trigger : quand un message est inséré → update ticket updated_at + unread flags
CREATE OR REPLACE FUNCTION public.support_on_new_message()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_admin THEN
    -- Admin a répondu → marquer unread_user = true, status = 'answered'
    UPDATE public.support_tickets
    SET unread_user  = TRUE,
        unread_admin = FALSE,
        status       = CASE WHEN status = 'closed' THEN 'closed' ELSE 'answered' END,
        updated_at   = NOW()
    WHERE id = NEW.ticket_id;
  ELSE
    -- User a écrit → marquer unread_admin = true
    UPDATE public.support_tickets
    SET unread_admin = TRUE,
        updated_at   = NOW()
    WHERE id = NEW.ticket_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_message_insert ON public.support_messages;
CREATE TRIGGER trg_support_message_insert
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.support_on_new_message();

-- ── 5. Realtime ───────────────────────────────────────────
DO $rt$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'support_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
  END IF;
END $rt$;
