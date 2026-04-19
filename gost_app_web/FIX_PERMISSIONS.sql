-- ============================================================
-- FIX PERMISSIONS POUR FREEMOPAY
-- Permet aux utilisateurs authentifiés de lire app_settings
-- ============================================================

-- Créer la table app_settings si elle n'existe pas
CREATE TABLE IF NOT EXISTS app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Activer RLS sur app_settings
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- Supprimer les anciennes politiques si elles existent
DROP POLICY IF EXISTS "Allow authenticated users to read app_settings" ON app_settings;
DROP POLICY IF EXISTS "Allow service role to manage app_settings" ON app_settings;

-- Permettre à TOUS les utilisateurs authentifiés de LIRE app_settings
CREATE POLICY "Allow authenticated users to read app_settings"
  ON app_settings
  FOR SELECT
  TO authenticated
  USING (true);

-- Permettre au service role de tout faire
CREATE POLICY "Allow service role to manage app_settings"
  ON app_settings
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Insérer la config par défaut si elle n'existe pas
INSERT INTO app_settings (key, value)
VALUES (
  'freemopay_config',
  '{
    "active": true,
    "baseUrl": "https://api-v2.freemopay.com",
    "appKey": "8381e965-51e0-42bd-b260-a78d9affa316",
    "secretKey": "hBbdnuQc3wlIch8HkuPb",
    "callbackUrl": "https://dqzrociaaztlezwlgzwh.supabase.co/functions/v1/freemopay-webhook",
    "paymentInitTimeout": 30,
    "statusCheckTimeout": 30,
    "tokenTimeout": 30,
    "tokenCacheDuration": 3000,
    "retryAttempts": 5,
    "retryDelay": 0.5
  }'::jsonb
)
ON CONFLICT (key) DO NOTHING;

-- Vérifier que tout fonctionne
SELECT
  key,
  value->>'active' as is_active,
  value->>'appKey' as app_key,
  value->>'callbackUrl' as callback_url
FROM app_settings
WHERE key = 'freemopay_config';
