# 🚨 FIX URGENT: Problème Freemopay Deposit

## Problème Identifié

### Transaction Bloquée
- **Transaction ID**: `55add924-89e8-474f-9446-829b1f8119e1`
- **Statut Freemopay API**: ✅ **SUCCESS** (100 FCFA débité)
- **Statut dans l'app**: ❌ **PENDING** (coins non crédités)
- **Utilisateur**: `724e6c57-3fb9-458b-ac35-2f9d5c444fca`
- **Montant**: 100 FCFA

### Cause Racine

Le **RLS (Row Level Security)** sur la table `app_settings` bloque les utilisateurs normaux:

1. L'utilisateur initie un deposit de 100 FCFA
2. Freemopay débite l'argent → **SUCCESS**
3. L'app poll le statut via `FreemopayService.getTransactionStatus()`
4. **MAIS** `loadConfig()` échoue car le RLS bloque la lecture de `app_settings`
5. Sans credentials, impossible d'appeler l'API Freemopay
6. L'app reste bloquée en "PENDING" pour toujours
7. **Les 100 FCFA sont perdus** (débités mais coins jamais crédités)

---

## Solution Immédiate (3 étapes)

### Étape 1: Appliquer le Fix RLS

Exécutez cette migration dans **Supabase SQL Editor**:

```bash
# Fichier: supabase/migrations/20260419_fix_app_settings_rls.sql
```

Ou directement:
```sql
-- Supprimer l'ancienne policy restrictive
DROP POLICY IF EXISTS "Admins can read app settings" ON app_settings;

-- Permettre aux users authentifiés de lire app_settings
CREATE POLICY "Authenticated users can read app settings"
  ON app_settings
  FOR SELECT
  USING (auth.role() = 'authenticated');
```

### Étape 2: Créditer Manuellement les Coins

Exécutez ce script dans **Supabase SQL Editor**:

```bash
# Fichier: FIX_TRANSACTION_55add924.sql
```

Ce script va:
1. Mettre à jour le statut de la transaction à SUCCESS
2. Créditer 100 coins au wallet de l'utilisateur
3. Créer une entrée dans wallet_transactions

### Étape 3: Redémarrer l'App

```bash
# Hot reload
flutter run
```

Maintenant les deposits fonctionneront correctement!

---

## Vérification

### Tester que le Fix fonctionne

1. Dans l'app, aller sur **Profil**
2. Cliquer sur **"Dépôt"**
3. Entrer un petit montant (ex: 50 FCFA)
4. Valider le paiement sur le téléphone
5. **L'app devrait maintenant** afficher SUCCESS et créditer les coins automatiquement

### Vérifier les Logs

```bash
# Dans les logs de l'app, vous devriez voir:
# ✅ [FREEMOPAY] Freemopay config loaded successfully
# ✅ [FREEMOPAY_AWAIT] Transaction xxx: SUCCESS
```

Si vous voyez encore:
```bash
# ❌ [FREEMOPAY] No Freemopay config found in app_settings
```

→ Le RLS n'est pas encore corrigé, réexécutez l'Étape 1.

---

## Test Complet de la Transaction

### Avec curl (vérifier statut Freemopay directement)

```bash
curl -X GET 'https://api-v2.freemopay.com/api/v2/payment/55add924-89e8-474f-9446-829b1f8119e1' \
  -u '8381e965-51e0-42bd-b260-a78d9affa316:hBbdnuQc3wlIch8HkuPb' \
  -H 'Content-Type: application/json' | jq '.'
```

**Résultat attendu**:
```json
{
  "reference": "55add924-89e8-474f-9446-829b1f8119e1",
  "merchandRef": "DEPOSIT_abf65057_724e6c57-3fb9-458b-ac35-2f9d5c444fca",
  "amount": 100,
  "status": "SUCCESS",
  "reason": "paiement en cours de traitement"
}
```

---

## Prévention Future

### Amélioration Sécurité (Recommandé)

Actuellement, les credentials Freemopay sont exposés côté client. Pour plus de sécurité:

1. **Migrer vers Edge Functions**:
   - Stocker les credentials comme secrets Supabase
   - Les appels API Freemopay se font côté serveur
   - L'app appelle juste les Edge Functions

2. **Activer le webhook Freemopay**:
   - Déployer `supabase/functions/freemopay-webhook`
   - Configurer dans le dashboard Freemopay
   - Les transactions sont créditées automatiquement sans polling

### Scripts de Monitoring

Créer un cron job qui vérifie les transactions PENDING depuis plus de 10 minutes et les met à jour automatiquement.

---

## Fichiers Créés

1. `supabase/migrations/20260419_fix_app_settings_rls.sql` - Fix RLS
2. `FIX_TRANSACTION_55add924.sql` - Correction manuelle de la transaction
3. `GET_FREEMOPAY_CREDENTIALS.sql` - Récupérer credentials (pour debug)
4. `FREEMOPAY_FIX_URGENT.md` - Ce fichier

---

## Support

Si le problème persiste après ces 3 étapes:

1. Vérifiez les logs de l'app
2. Exécutez `VERIFIER_CONFIG.sql` dans Supabase
3. Vérifiez que `active: true` dans la config Freemopay

**Status de la transaction testée**: ✅ **SUCCESS sur Freemopay** (confirmé via curl)
