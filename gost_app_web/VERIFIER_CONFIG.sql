-- ============================================================
-- VÉRIFIER LA CONFIGURATION FREEMOPAY
-- ============================================================

-- Afficher la config complète
SELECT
  key,
  value->>'active' as is_active,
  value->>'baseUrl' as base_url,
  LEFT(value->>'appKey', 20) || '...' as app_key_preview,
  '***SECRET***' as secret_key_hidden,
  value->>'callbackUrl' as callback_url
FROM app_settings
WHERE key = 'freemopay_config';

-- Vérifier les permissions RLS
SELECT
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE tablename = 'app_settings'
ORDER BY policyname;
