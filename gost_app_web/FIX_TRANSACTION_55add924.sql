-- ============================================================
-- CORRECTION MANUELLE: Transaction 55add924-89e8-474f-9446-829b1f8119e1
-- Status réel sur Freemopay: SUCCESS (100 FCFA payé)
-- Status dans l'app: PENDING (coins non crédités)
-- ============================================================

-- 1. Vérifier la transaction dans freemopay_transactions
SELECT
  'Transaction dans DB:' as info,
  reference,
  user_id,
  transaction_type,
  amount,
  status,
  payer_or_receiver,
  message,
  created_at
FROM freemopay_transactions
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- 2. Mettre à jour le statut de la transaction
UPDATE freemopay_transactions
SET
  status = 'SUCCESS',
  message = 'paiement en cours de traitement',
  updated_at = NOW()
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- 3. Récupérer l'user_id et le montant
DO $$
DECLARE
  v_user_id UUID;
  v_amount INT;
  v_reference TEXT := '55add924-89e8-474f-9446-829b1f8119e1';
BEGIN
  -- Récupérer les infos de la transaction
  SELECT user_id, amount
  INTO v_user_id, v_amount
  FROM freemopay_transactions
  WHERE reference = v_reference;

  -- Vérifier que la transaction existe
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'Transaction not found: %', v_reference;
    RETURN;
  END IF;

  RAISE NOTICE 'User ID: %, Amount: %', v_user_id, v_amount;

  -- Créditer le wallet de l'utilisateur
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
  SELECT
    v_user_id,
    v_amount,
    COALESCE((SELECT balance FROM wallets WHERE user_id = v_user_id), 0) + v_amount,
    'credit',
    'freemopay_deposit',
    v_reference,
    'Dépôt Mobile Money - Correction manuelle (transaction SUCCESS sur Freemopay)',
    NOW();

  -- Mettre à jour le solde du wallet
  INSERT INTO wallets (user_id, balance, updated_at)
  VALUES (v_user_id, v_amount, NOW())
  ON CONFLICT (user_id)
  DO UPDATE SET
    balance = wallets.balance + v_amount,
    updated_at = NOW();

  RAISE NOTICE 'Wallet credited successfully: % coins', v_amount;
END $$;

-- 4. Vérifier le résultat
SELECT
  'Wallet après correction:' as info,
  w.user_id,
  w.balance,
  w.updated_at
FROM wallets w
WHERE w.user_id = (
  SELECT user_id FROM freemopay_transactions
  WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
);

-- 5. Vérifier la dernière transaction wallet
SELECT
  'Dernière transaction wallet:' as info,
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
