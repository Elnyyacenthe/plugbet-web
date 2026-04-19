-- ============================================================
-- SCRIPT DE DEBUG FREEMOPAY
-- Exécutez ce script pour diagnostiquer le problème
-- ============================================================

-- 1. Vérifier si la table app_settings existe
SELECT EXISTS (
  SELECT FROM information_schema.tables
  WHERE table_schema = 'public'
  AND table_name = 'app_settings'
) AS app_settings_exists;

-- 2. Vérifier si la config freemopay existe
SELECT * FROM app_settings WHERE key = 'freemopay_config';

-- 3. Vérifier les politiques RLS sur app_settings
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'app_settings';

-- 4. Vérifier si RLS est activé sur app_settings
SELECT
  tablename,
  rowsecurity
FROM pg_tables
WHERE tablename = 'app_settings';
