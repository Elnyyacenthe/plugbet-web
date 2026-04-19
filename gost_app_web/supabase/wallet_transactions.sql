-- ============================================================
-- wallet_transactions — Audit trail de toutes les operations wallet
-- + RPC atomique wallet_apply_delta pour eviter les race conditions
-- ============================================================

-- 1. Table d'historique
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delta          INT NOT NULL,            -- positif = credit, negatif = debit
  source         TEXT NOT NULL,           -- 'aviator','apple_fortune','checkers',...
  reference_id   TEXT,                    -- id de session/round/game
  balance_before INT NOT NULL,
  balance_after  INT NOT NULL,
  note           TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created
  ON wallet_transactions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_source
  ON wallet_transactions(source, created_at DESC);

-- 2. RLS : chaque user lit uniquement ses propres transactions
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Read own transactions" ON wallet_transactions;
CREATE POLICY "Read own transactions"
  ON wallet_transactions FOR SELECT
  USING (auth.uid() = user_id);

-- Aucun INSERT/UPDATE/DELETE direct — uniquement via RPC
DROP POLICY IF EXISTS "No direct insert tx" ON wallet_transactions;
CREATE POLICY "No direct insert tx"
  ON wallet_transactions FOR INSERT
  WITH CHECK (false);


-- 3. RPC atomique : applique un delta au wallet + enregistre la tx
-- Retourne le nouveau balance ou NULL si refuse (solde insuffisant)
CREATE OR REPLACE FUNCTION wallet_apply_delta(
  p_user_id       UUID,
  p_delta         INT,
  p_source        TEXT,
  p_reference_id  TEXT DEFAULT NULL,
  p_note          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current  INT;
  v_new      INT;
BEGIN
  -- Auth : soit l'utilisateur lui-meme, soit un SECURITY DEFINER depuis une autre RPC
  -- (on ne verifie pas auth.uid() ici car cette fonction peut etre appelee
  -- depuis d'autres RPCs SECURITY DEFINER type create_apple_fortune_session)

  -- Lock la ligne
  SELECT coins INTO v_current
    FROM user_profiles
    WHERE id = p_user_id
    FOR UPDATE;

  IF v_current IS NULL THEN
    RETURN jsonb_build_object('error', 'user_not_found');
  END IF;

  v_new := v_current + p_delta;

  -- Debit : refuse si solde insuffisant
  IF p_delta < 0 AND v_new < 0 THEN
    RETURN jsonb_build_object(
      'error', 'insufficient_balance',
      'current', v_current,
      'requested', -p_delta
    );
  END IF;

  -- Applique
  UPDATE user_profiles
    SET coins = v_new
    WHERE id = p_user_id;

  -- Enregistre la tx
  INSERT INTO wallet_transactions (
    user_id, delta, source, reference_id,
    balance_before, balance_after, note
  ) VALUES (
    p_user_id, p_delta, p_source, p_reference_id,
    v_current, v_new, p_note
  );

  RETURN jsonb_build_object(
    'balance_before', v_current,
    'balance_after', v_new,
    'delta', p_delta
  );
END;
$$;


-- 4. Version publique : uniquement pour l'utilisateur lui-meme
-- (sans SECURITY DEFINER bypass, verifie auth.uid())
CREATE OR REPLACE FUNCTION my_wallet_apply_delta(
  p_delta         INT,
  p_source        TEXT,
  p_reference_id  TEXT DEFAULT NULL,
  p_note          TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  RETURN wallet_apply_delta(v_uid, p_delta, p_source, p_reference_id, p_note);
END;
$$;
