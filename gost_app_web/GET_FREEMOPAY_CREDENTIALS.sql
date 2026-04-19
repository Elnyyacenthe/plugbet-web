-- ============================================================
-- RÉCUPÉRER LES CREDENTIALS FREEMOPAY
-- Exécutez ce script dans la console Supabase SQL Editor
-- ============================================================

-- 1. Vérifier que la config existe
SELECT
  'Configuration exists:' as status,
  CASE WHEN EXISTS (SELECT 1 FROM app_settings WHERE key = 'freemopay_config')
    THEN 'YES'
    ELSE 'NO - Run migration first!'
  END as result;

-- 2. Afficher la config complète (ATTENTION: contient les secrets!)
SELECT
  key,
  value->>'active' as is_active,
  value->>'baseUrl' as base_url,
  value->>'appKey' as app_key,
  value->>'secretKey' as secret_key,
  value->>'callbackUrl' as callback_url
FROM app_settings
WHERE key = 'freemopay_config';

-- 3. Vérifier la transaction spécifique
SELECT
  reference,
  external_id,
  transaction_type,
  amount,
  status,
  payer_or_receiver,
  message,
  created_at,
  updated_at
FROM freemopay_transactions
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- 4. Instructions pour tester avec curl
-- Une fois que vous avez les credentials ci-dessus, exécutez cette commande dans votre terminal:
/*

export APP_KEY="<copiez app_key ci-dessus>"
export SECRET_KEY="<copiez secret_key ci-dessus>"

# Tester la transaction
curl -X GET 'https://api-v2.freemopay.com/api/v2/payment/55add924-89e8-474f-9446-829b1f8119e1' \
  -u "$APP_KEY:$SECRET_KEY" \
  -H 'Content-Type: application/json' | jq '.'

*/
