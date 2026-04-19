-- ============================================================
-- EXPLORATION DE LA BASE DE DONNÉES SUPABASE
-- Exécutez ce script dans Supabase SQL Editor pour voir toute l'architecture
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- PARTIE 1: LISTER TOUTES LES TABLES
-- ═══════════════════════════════════════════════════════════

SELECT
  '📋 Tables dans le schema public:' as info,
  tablename as table_name,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 2: STRUCTURE DE user_profiles
-- ═══════════════════════════════════════════════════════════

SELECT
  '👤 Structure de user_profiles:' as info,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_profiles'
ORDER BY ordinal_position;

-- Exemple de données
SELECT
  '👤 Exemple de données user_profiles:' as info,
  id,
  username,
  coins,
  created_at
FROM user_profiles
LIMIT 3;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 3: STRUCTURE DE wallet_transactions
-- ═══════════════════════════════════════════════════════════

SELECT
  '💰 Structure de wallet_transactions:' as info,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'wallet_transactions'
ORDER BY ordinal_position;

-- Exemple de transactions
SELECT
  '💰 Exemple de wallet_transactions:' as info,
  id,
  user_id,
  amount,
  balance_after,
  type,
  source,
  created_at
FROM wallet_transactions
ORDER BY created_at DESC
LIMIT 5;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 4: STRUCTURE DE freemopay_transactions
-- ═══════════════════════════════════════════════════════════

SELECT
  '💳 Structure de freemopay_transactions:' as info,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'freemopay_transactions'
ORDER BY ordinal_position;

-- Toutes les transactions Freemopay
SELECT
  '💳 Toutes les transactions Freemopay:' as info,
  reference,
  user_id,
  transaction_type,
  amount,
  status,
  payer_or_receiver,
  message,
  created_at
FROM freemopay_transactions
ORDER BY created_at DESC;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 5: VÉRIFIER LES RPCs (fonctions)
-- ═══════════════════════════════════════════════════════════

SELECT
  '⚙️  RPCs disponibles:' as info,
  routine_name as rpc_name,
  routine_type,
  data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%wallet%'
ORDER BY routine_name;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 6: VÉRIFIER app_settings
-- ═══════════════════════════════════════════════════════════

SELECT
  '⚙️  Structure de app_settings:' as info,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_settings'
ORDER BY ordinal_position;

-- Config Freemopay
SELECT
  '💳 Config Freemopay:' as info,
  key,
  value->>'active' as is_active,
  value->>'baseUrl' as base_url,
  LEFT(value->>'appKey', 15) || '...' as app_key_preview,
  value->>'callbackUrl' as callback_url
FROM app_settings
WHERE key = 'freemopay_config';

-- ═══════════════════════════════════════════════════════════
-- PARTIE 7: STATISTIQUES
-- ═══════════════════════════════════════════════════════════

-- Nombre total d'utilisateurs
SELECT
  'Statistiques générales:' as info,
  COUNT(*) as total_users,
  SUM(coins) as total_coins,
  AVG(coins) as avg_coins_per_user
FROM user_profiles;

-- Transactions Freemopay par statut
SELECT
  'Freemopay - Par statut:' as info,
  status,
  COUNT(*) as count,
  SUM(amount) as total_amount
FROM freemopay_transactions
GROUP BY status;

-- Transactions Freemopay par type
SELECT
  'Freemopay - Par type:' as info,
  transaction_type,
  COUNT(*) as count,
  SUM(amount) as total_amount
FROM freemopay_transactions
GROUP BY transaction_type;
