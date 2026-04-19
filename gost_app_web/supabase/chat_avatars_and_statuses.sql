-- ============================================================
-- Chat Avatars + Statuts (stories 24h) — WhatsApp-like
-- ============================================================

-- 1. Avatar URL sur user_profiles
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;


-- 2. Table user_statuses (stories/statuts 24h)
CREATE TABLE IF NOT EXISTS user_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  media_url   TEXT NOT NULL,
  media_type  TEXT NOT NULL DEFAULT 'image' CHECK (media_type IN ('image','text')),
  caption     TEXT,
  bg_color    TEXT, -- pour statuts texte seulement
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_user_statuses_user_id
  ON user_statuses(user_id);

CREATE INDEX IF NOT EXISTS idx_user_statuses_expires_at
  ON user_statuses(expires_at);


-- 3. Table status_views (qui a vu quoi)
CREATE TABLE IF NOT EXISTS status_views (
  status_id  UUID NOT NULL REFERENCES user_statuses(id) ON DELETE CASCADE,
  viewer_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (status_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS idx_status_views_viewer
  ON status_views(viewer_id);


-- 4. RLS
ALTER TABLE user_statuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE status_views ENABLE ROW LEVEL SECURITY;

-- Lire les statuts actifs (non expires) de tout le monde
DROP POLICY IF EXISTS "Read active statuses" ON user_statuses;
CREATE POLICY "Read active statuses"
  ON user_statuses FOR SELECT
  USING (expires_at > now());

-- Creer ses propres statuts
DROP POLICY IF EXISTS "Create own status" ON user_statuses;
CREATE POLICY "Create own status"
  ON user_statuses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Supprimer ses propres statuts
DROP POLICY IF EXISTS "Delete own status" ON user_statuses;
CREATE POLICY "Delete own status"
  ON user_statuses FOR DELETE
  USING (auth.uid() = user_id);

-- Lire les vues sur ses propres statuts
DROP POLICY IF EXISTS "Read own status views" ON status_views;
CREATE POLICY "Read own status views"
  ON status_views FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_statuses s
      WHERE s.id = status_views.status_id AND s.user_id = auth.uid()
    )
    OR viewer_id = auth.uid()
  );

-- Enregistrer sa propre vue
DROP POLICY IF EXISTS "Insert own view" ON status_views;
CREATE POLICY "Insert own view"
  ON status_views FOR INSERT
  WITH CHECK (auth.uid() = viewer_id);


-- 5. Fonction de nettoyage des statuts expires (optionnel, a appeler via cron)
CREATE OR REPLACE FUNCTION cleanup_expired_statuses()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted INT;
BEGIN
  DELETE FROM user_statuses WHERE expires_at < now() - INTERVAL '1 day';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
