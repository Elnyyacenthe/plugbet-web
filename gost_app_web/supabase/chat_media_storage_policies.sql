-- ============================================================
-- Storage bucket 'chat-media' — Policies
-- Upload avatars, statuts, images de chat
-- ============================================================

-- 1. Creer le bucket s'il n'existe pas (public = true pour lecture libre)
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', true)
ON CONFLICT (id) DO UPDATE SET public = true;


-- 2. Policies sur storage.objects pour ce bucket
-- On autorise les utilisateurs authentifies a uploader leurs propres fichiers
-- et tout le monde a les lire (bucket public).

-- Lecture publique
DROP POLICY IF EXISTS "chat-media public read" ON storage.objects;
CREATE POLICY "chat-media public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat-media');

-- Upload authentifie
DROP POLICY IF EXISTS "chat-media authenticated upload" ON storage.objects;
CREATE POLICY "chat-media authenticated upload"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'chat-media');

-- Update (pour upsert des avatars)
DROP POLICY IF EXISTS "chat-media authenticated update" ON storage.objects;
CREATE POLICY "chat-media authenticated update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'chat-media');

-- Delete (pour supprimer ses propres fichiers)
DROP POLICY IF EXISTS "chat-media authenticated delete" ON storage.objects;
CREATE POLICY "chat-media authenticated delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'chat-media');
