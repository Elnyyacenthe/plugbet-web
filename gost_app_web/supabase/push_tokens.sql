-- ============================================================
-- push_tokens — Stockage des tokens FCM pour notifications push
-- ============================================================

CREATE TABLE IF NOT EXISTS push_tokens (
  token      TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform   TEXT NOT NULL CHECK (platform IN ('android','ios','web')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user
  ON push_tokens(user_id);

-- RLS
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

-- L'utilisateur peut lire/ecrire ses propres tokens
DROP POLICY IF EXISTS "Read own push tokens" ON push_tokens;
CREATE POLICY "Read own push tokens"
  ON push_tokens FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Upsert own push token" ON push_tokens;
CREATE POLICY "Upsert own push token"
  ON push_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Update own push token" ON push_tokens;
CREATE POLICY "Update own push token"
  ON push_tokens FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Delete own push token" ON push_tokens;
CREATE POLICY "Delete own push token"
  ON push_tokens FOR DELETE
  USING (auth.uid() = user_id);

-- Fonction helper pour enregistrer/mettre a jour un token
CREATE OR REPLACE FUNCTION register_push_token(
  p_token    TEXT,
  p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  INSERT INTO push_tokens (token, user_id, platform)
    VALUES (p_token, auth.uid(), p_platform)
    ON CONFLICT (token) DO UPDATE SET
      user_id = auth.uid(),
      updated_at = now();
END;
$$;
