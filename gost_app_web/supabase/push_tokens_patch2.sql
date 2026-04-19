-- ============================================================
-- Patch 2 : RPC register_push_token sans ON CONFLICT
-- Compatible avec n'importe quel schema existant de push_tokens
-- ============================================================

CREATE OR REPLACE FUNCTION register_push_token(
  p_token    TEXT,
  p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;

  -- Essayer update d'abord
  UPDATE push_tokens
    SET user_id = v_uid,
        platform = p_platform,
        updated_at = now()
    WHERE token = p_token;

  -- Si rien n'a ete update, inserer
  IF NOT FOUND THEN
    INSERT INTO push_tokens (token, user_id, platform, updated_at)
      VALUES (p_token, v_uid, p_platform, now());
  END IF;
END;
$$;
