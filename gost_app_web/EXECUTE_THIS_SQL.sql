-- ============================================================
-- EXÉCUTER CE SQL DANS SUPABASE SQL EDITOR
-- Pour créer la table freemopay_transactions
-- ============================================================

-- Table des transactions Freemopay
CREATE TABLE IF NOT EXISTS freemopay_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  reference TEXT UNIQUE NOT NULL,
  external_id TEXT NOT NULL,
  transaction_type TEXT NOT NULL, -- 'DEPOSIT' ou 'WITHDRAW'
  amount INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'SUCCESS', 'FAILED'
  payer_or_receiver TEXT, -- Numéro de téléphone
  message TEXT,
  callback_data JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index pour performances
CREATE INDEX IF NOT EXISTS idx_freemopay_user ON freemopay_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_freemopay_reference ON freemopay_transactions(reference);
CREATE INDEX IF NOT EXISTS idx_freemopay_status ON freemopay_transactions(status);
CREATE INDEX IF NOT EXISTS idx_freemopay_external_id ON freemopay_transactions(external_id);

-- RLS pour freemopay_transactions
ALTER TABLE freemopay_transactions ENABLE ROW LEVEL SECURITY;

-- Les utilisateurs peuvent voir leurs propres transactions
CREATE POLICY "Users can read own freemopay transactions"
  ON freemopay_transactions
  FOR SELECT
  USING (auth.uid() = user_id);

-- Les utilisateurs peuvent créer leurs propres transactions
CREATE POLICY "Users can insert own freemopay transactions"
  ON freemopay_transactions
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Service role peut tout faire (pour webhook)
CREATE POLICY "Service role can manage freemopay transactions"
  ON freemopay_transactions
  FOR ALL
  USING (auth.role() = 'service_role');

-- Trigger pour updated_at
CREATE OR REPLACE FUNCTION update_freemopay_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER freemopay_transactions_updated_at
  BEFORE UPDATE ON freemopay_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_freemopay_updated_at();

-- ✅ TERMINÉ !
-- Vous pouvez maintenant tester l'app mobile
