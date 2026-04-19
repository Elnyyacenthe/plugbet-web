-- ============================================================
-- FIX FREEMOPAY - VERSION CORRIGÉE
-- Architecture réelle: user_profiles.coins + RPC my_wallet_apply_delta
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- PARTIE 1: FIX RLS sur app_settings
-- ═══════════════════════════════════════════════════════════

-- Supprimer l'ancienne policy restrictive
DROP POLICY IF EXISTS "Admins can read app settings" ON app_settings;

-- Permettre aux utilisateurs authentifiés de lire app_settings
-- (nécessaire pour que FreemopayService.loadConfig() fonctionne)
CREATE POLICY "Authenticated users can read app_settings"
  ON app_settings
  FOR SELECT
  USING (auth.role() = 'authenticated');

SELECT '✅ RLS corrigé - Les users peuvent maintenant lire app_settings' as status;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 2: VÉRIFIER LA TRANSACTION 55add924
-- ═══════════════════════════════════════════════════════════

-- Afficher la transaction
SELECT
  '📋 Transaction 55add924:' as info,
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

-- ═══════════════════════════════════════════════════════════
-- PARTIE 3: METTRE À JOUR LE STATUT
-- ═══════════════════════════════════════════════════════════

UPDATE freemopay_transactions
SET
  status = 'SUCCESS',
  message = 'paiement en cours de traitement - Correction manuelle',
  updated_at = NOW()
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
RETURNING
  '✅ Statut mis à jour:' as info,
  reference,
  status,
  message;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 4: CRÉDITER LES COINS via RPC (SI ELLE EXISTE)
-- ═══════════════════════════════════════════════════════════

-- Cette commande appelle la RPC my_wallet_apply_delta pour créditer les coins
-- Si la RPC n'existe pas, passez à la PARTIE 5 (fallback)

DO $$
DECLARE
  v_user_id UUID;
  v_amount INT;
  v_reference TEXT := '55add924-89e8-474f-9446-829b1f8119e1';
  v_rpc_exists BOOLEAN;
BEGIN
  -- Récupérer user_id et amount
  SELECT user_id, amount
  INTO v_user_id, v_amount
  FROM freemopay_transactions
  WHERE reference = v_reference;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ Transaction not found: %', v_reference;
    RETURN;
  END IF;

  RAISE NOTICE '📝 User: % | Amount: %', v_user_id, v_amount;

  -- Vérifier si la RPC my_wallet_apply_delta existe
  SELECT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'my_wallet_apply_delta'
  ) INTO v_rpc_exists;

  IF v_rpc_exists THEN
    -- Utiliser la RPC (méthode atomique recommandée)
    RAISE NOTICE '⚙️  Appel de la RPC my_wallet_apply_delta...';

    PERFORM my_wallet_apply_delta(
      p_user_id => v_user_id,
      p_delta => v_amount,
      p_source => 'freemopay_deposit',
      p_reference_id => v_reference,
      p_note => 'Dépôt Mobile Money - Correction manuelle (SUCCESS sur Freemopay)'
    );

    RAISE NOTICE '✅ Coins crédités via RPC: % coins', v_amount;
  ELSE
    -- Fallback: Méthode directe (non-atomique)
    RAISE NOTICE '⚠️  RPC my_wallet_apply_delta n''existe pas - Fallback direct';
    RAISE NOTICE '⚠️  Exécutez la PARTIE 5 manuellement ci-dessous';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 5: FALLBACK DIRECT (SI RPC N'EXISTE PAS)
-- Décommentez cette section si la PARTIE 4 a échoué
-- ═══════════════════════════════════════════════════════════

/*
-- Mettre à jour les coins directement dans user_profiles
DO $$
DECLARE
  v_user_id UUID;
  v_amount INT;
  v_reference TEXT := '55add924-89e8-474f-9446-829b1f8119e1';
  v_current_coins INT;
BEGIN
  -- Récupérer user_id et amount
  SELECT user_id, amount
  INTO v_user_id, v_amount
  FROM freemopay_transactions
  WHERE reference = v_reference;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ Transaction not found';
    RETURN;
  END IF;

  -- Récupérer le solde actuel
  SELECT COALESCE(coins, 0)
  INTO v_current_coins
  FROM user_profiles
  WHERE id = v_user_id;

  RAISE NOTICE 'Solde avant: % coins', v_current_coins;

  -- Créditer les coins
  UPDATE user_profiles
  SET coins = coins + v_amount
  WHERE id = v_user_id;

  -- Créer une entrée dans wallet_transactions (si la table existe)
  INSERT INTO wallet_transactions (
    user_id,
    amount,
    balance_after,
    type,
    source,
    reference_id,
    note
  )
  VALUES (
    v_user_id,
    v_amount,
    v_current_coins + v_amount,
    'credit',
    'freemopay_deposit',
    v_reference,
    'Dépôt Mobile Money - Correction manuelle (SUCCESS sur Freemopay)'
  );

  RAISE NOTICE '✅ % coins ajoutés | Nouveau solde: %', v_amount, v_current_coins + v_amount;
END $$;
*/

-- ═══════════════════════════════════════════════════════════
-- PARTIE 6: VÉRIFICATIONS FINALES
-- ═══════════════════════════════════════════════════════════

-- Vérifier le profil de l'utilisateur
SELECT
  '✅ Profil utilisateur:' as info,
  up.id,
  up.username,
  up.coins as balance,
  up.updated_at
FROM user_profiles up
WHERE up.id = (
  SELECT user_id FROM freemopay_transactions
  WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1'
);

-- Vérifier la transaction Freemopay
SELECT
  '✅ Transaction Freemopay:' as info,
  reference,
  status,
  amount,
  message,
  updated_at
FROM freemopay_transactions
WHERE reference = '55add924-89e8-474f-9446-829b1f8119e1';

-- Vérifier les dernières transactions wallet (si la table existe)
SELECT
  '✅ Dernières transactions wallet:' as info,
  user_id,
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
LIMIT 3;

-- ═══════════════════════════════════════════════════════════
-- PARTIE 7: LISTER AUTRES TRANSACTIONS PENDING
-- ═══════════════════════════════════════════════════════════

-- Afficher toutes les transactions PENDING de plus de 5 minutes
SELECT
  '⚠️  Autres transactions PENDING:' as info,
  reference,
  user_id,
  transaction_type,
  amount,
  created_at,
  EXTRACT(EPOCH FROM (NOW() - created_at))/60 as minutes_ago
FROM freemopay_transactions
WHERE status = 'PENDING'
  AND created_at < NOW() - INTERVAL '5 minutes'
ORDER BY created_at DESC;

-- Instructions finales
SELECT '
🎉 FIX APPLIQUÉ!

✅ RLS corrigé - Les nouveaux deposits fonctionneront
✅ Transaction 55add924 mise à jour à SUCCESS

📱 Prochaines étapes:
1. Redémarrer l''app (flutter run)
2. Vérifier que le solde a augmenté de 100 coins
3. Tester un nouveau deposit (petit montant: 50 FCFA)
4. Vérifier l''historique des transactions

⚠️  Si d''autres transactions PENDING existent ci-dessus:
   - Testez chaque référence avec curl (voir FREEMOPAY_FIX_URGENT.md)
   - Créditez manuellement les SUCCESS
' as instructions;
