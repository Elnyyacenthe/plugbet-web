-- ============================================================
-- rate_limits — Throttle anti-abus pour les RPC critiques
-- Table legere qui stocke (user_id, action) → timestamp
-- ============================================================

CREATE TABLE IF NOT EXISTS rate_limits (
  user_id     UUID NOT NULL,
  action      TEXT NOT NULL,
  last_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  count_window INT NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, action)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_last_at
  ON rate_limits(last_at);


-- Fonction helper : renvoie true si l'action est autorisee,
-- false si l'utilisateur a deja effectue cette action dans
-- la fenetre temporelle specifiee.
--
-- Usage dans une RPC :
--   IF NOT check_rate_limit(auth.uid(), 'create_session', 500) THEN
--     RETURN jsonb_build_object('error', 'rate_limited');
--   END IF;
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_user_id      UUID,
  p_action       TEXT,
  p_window_ms    INT DEFAULT 500
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL THEN RETURN false; END IF;

  SELECT last_at INTO v_existing
    FROM rate_limits
    WHERE user_id = p_user_id AND action = p_action
    FOR UPDATE;

  IF v_existing IS NOT NULL
     AND v_existing > now() - (p_window_ms || ' milliseconds')::interval THEN
    RETURN false; -- trop tot
  END IF;

  INSERT INTO rate_limits (user_id, action, last_at)
    VALUES (p_user_id, p_action, now())
    ON CONFLICT (user_id, action)
    DO UPDATE SET last_at = now(),
                  count_window = rate_limits.count_window + 1;

  RETURN true;
END;
$$;


-- Nettoyage periodique des entrees anciennes (> 1h)
CREATE OR REPLACE FUNCTION cleanup_rate_limits()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_deleted INT;
BEGIN
  DELETE FROM rate_limits WHERE last_at < now() - INTERVAL '1 hour';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
