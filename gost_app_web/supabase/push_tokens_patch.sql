-- ============================================================
-- Patch : ajouter updated_at + platform a la table push_tokens existante
-- (la table avait ete creee sans ces colonnes)
-- ============================================================

-- 1. Colonnes manquantes
ALTER TABLE push_tokens
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE push_tokens
  ADD COLUMN IF NOT EXISTS platform TEXT NOT NULL DEFAULT 'android';

-- Si platform existait deja sans CHECK, on ajoute la contrainte
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'push_tokens_platform_check'
  ) THEN
    ALTER TABLE push_tokens
      ADD CONSTRAINT push_tokens_platform_check
      CHECK (platform IN ('android','ios','web'));
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

-- 2. Recreer la RPC pour s'assurer qu'elle est a jour
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
  INSERT INTO push_tokens (token, user_id, platform, updated_at)
    VALUES (p_token, auth.uid(), p_platform, now())
    ON CONFLICT (token) DO UPDATE SET
      user_id = auth.uid(),
      platform = EXCLUDED.platform,
      updated_at = now();
END;
$$;

-- 3. Verifier que les policies sont en place (idempotent)
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

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
