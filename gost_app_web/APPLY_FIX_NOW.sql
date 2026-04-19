-- ============================================================
-- FIX IMMÉDIAT: Corriger le RLS et la transaction bloquée
-- Exécutez TOUT ce script dans Supabase SQL Editor
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- PARTIE 1: FIX RLS (permet aux users de lire app_settings)
-- ════════════════════════════════════════════════════════════

-- Supprimer l'ancienne policy restrictive
DROP POLICY IF EXISTS "Admins can read app settings" ON app_settings;

-- Nouvelle policy: Tous les utilisateurs authentifiés peuvent lire app_settings
CREATE POLICY "Authenticated users can read app_settings"
  ON app_settings
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Vérifier que la policy est créée
SELECT 'RLS Policy créée:' as status, policyname
FROM pg_policies
WHERE tablename = 'app_settings' AND policyname = 'Authenticated users can read app_settings';

-- ════════════════════════════════════════════════════════════
-- PARTIE 2: CRÉDITER LA TRANSACTION 55add924 (100 FCFA)
-- ════════════════════════════════════════════════════════════

-- Vérifier la transaction
SELECT
  'Transaction avant fix:' as info,
  reference,
  user_id,
  transaction_type,
  amount,
  status,
  payer_or_receiver,
  created_at
FROM freemopay_transactions
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- Mettre à jour le statut
UPDATE freemopay_transactions
SET
  status = 'SUCCESS',
  message = 'paiement en cours de traitement - Correction manuelle',
  updated_at = NOW()
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
RETURNING reference, status, message;

-- Créditer le wallet
DO $$
DECLARE
  v_user_id UUID;
  v_amount INT;
  v_reference TEXT := '55add924-89e8-474f-9446-829b1f8119e1';
  v_current_balance INT;
BEGIN
  -- Récupérer user_id et amount
  SELECT user_id, amount
  INTO v_user_id, v_amount
  FROM freemopay_transactions
  WHERE reference = v_reference;

  IF v_user_id IS NULL THEN
    RAISE NOTICE 'Transaction not found: %', v_reference;
    RETURN;
  END IF;

  -- Récupérer le solde actuel
  SELECT COALESCE(balance, 0)
  INTO v_current_balance
  FROM wallets
  WHERE user_id = v_user_id;

  RAISE NOTICE 'User: % | Amount: % | Balance avant: %', v_user_id, v_amount, v_current_balance;

  -- Créer la transaction wallet
  INSERT INTO wallet_transactions (
    user_id,
    amount,
    balance_after,
    type,
    source,
    reference_id,
    note,
    created_at
  )
  VALUES (
    v_user_id,
    v_amount,
    v_current_balance + v_amount,
    'credit',
    'freemopay_deposit',
    v_reference,
    'Dépôt Mobile Money - Fix manuel (SUCCESS sur Freemopay)',
    NOW()
  );

  -- Mettre à jour le wallet
  INSERT INTO wallets (user_id, balance, updated_at)
  VALUES (v_user_id, v_amount, NOW())
  ON CONFLICT (user_id)
  DO UPDATE SET
    balance = wallets.balance + v_amount,
    updated_at = NOW();

  RAISE NOTICE '✅ Wallet crédité: % coins ajoutés', v_amount;
END $$;

-- ════════════════════════════════════════════════════════════
-- PARTIE 3: VÉRIFICATION
-- ════════════════════════════════════════════════════════════

-- Vérifier la transaction
SELECT
  '✅ Transaction après fix:' as info,
  reference,
  status,
  amount,
  message,
  updated_at
FROM freemopay_transactions
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- Vérifier le wallet
SELECT
  '✅ Wallet après fix:' as info,
  w.user_id,
  w.balance,
  w.updated_at
FROM wallets w
WHERE w.user_id = (
  SELECT user_id FROM freemopay_transactions
  WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
);

-- Vérifier les dernières transactions wallet
SELECT
  '✅ Dernières transactions wallet:' as info,
  type,
  amount,
  balance_after,
  source,
  note,
  created_at
FROM wallet_transactions
WHERE user_id = (
  SELECT user_id FROM freemopay_transactions
  WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
)
ORDER BY created_at DESC
LIMIT 5;

-- ════════════════════════════════════════════════════════════
-- PARTIE 4: TOUTES LES TRANSACTIONS PENDING (auto-fix)
-- ════════════════════════════════════════════════════════════

-- Lister toutes les transactions PENDING de plus de 5 minutes
SELECT
  '⚠️  Autres transactions PENDING:' as info,
  reference,
  user_id,
  transaction_type,
  amount,
  status,
  created_at,
  EXTRACT(EPOCH FROM (NOW() - created_at))/60 as minutes_ago
FROM freemopay_transactions
WHERE status = 'PENDING'
  AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY created_at DESC;

-- Instructions pour auto-fix
SELECT '
📝 Pour fixer automatiquement TOUTES les transactions PENDING:

1. Testez chaque référence avec curl:
   curl -X GET "https://api-v2.freemopay.com/api/v2/payment/REFERENCE" \
     -u "8381e965-51e0-42bd-b260-a78d9affa316:hBbdnuQc3wlIch8HkuPb"

2. Si status=SUCCESS, exécutez le même code que ci-dessus avec la nouvelle référence

✅ Le RLS est maintenant corrigé - Les nouveaux deposits fonctionneront!
' as instructions;
