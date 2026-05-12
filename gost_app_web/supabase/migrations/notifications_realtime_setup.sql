-- ============================================================
-- NOTIFICATIONS REALTIME SETUP (idempotent)
-- ============================================================
-- A executer une seule fois. Garantit que les tables critiques
-- pour les notifications client sont bien dans la publication
-- `supabase_realtime` (sinon le client ne recoit aucun event INSERT).
--
-- Concerne :
--   - private_messages    -> notif locale de chat (NotificationService.subscribeToChatMessages)
--   - app_announcements   -> notif locale d'annonce admin (NotificationService.subscribeToAnnouncements)
--   - conversations       -> rafraichir la liste de conversations
-- ============================================================

DO $rt$
DECLARE
  v_tables TEXT[] := ARRAY['private_messages', 'app_announcements', 'conversations'];
  v_t      TEXT;
BEGIN
  FOREACH v_t IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = v_t
    ) THEN
      BEGIN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_t);
        RAISE NOTICE 'Added % to supabase_realtime publication', v_t;
      EXCEPTION WHEN undefined_table THEN
        RAISE NOTICE 'Table % does not exist, skipped', v_t;
      END;
    ELSE
      RAISE NOTICE 'Table % already in publication', v_t;
    END IF;
  END LOOP;
END $rt$;

-- ─── Verification ─────────────────────────────────────────
SELECT
  tablename,
  'in_realtime' AS status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('private_messages', 'app_announcements', 'conversations')
ORDER BY tablename;
