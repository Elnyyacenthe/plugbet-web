# Guide de Configuration Freemopay

## 📋 Aperçu

L'intégration Freemopay permet aux utilisateurs de :
- **Déposer** de l'argent (Mobile Money → Coins) : 1 FCFA = 1 coin
- **Retirer** de l'argent (Coins → Mobile Money) : 1 coin = 1 FCFA

## 🚀 Étapes de Configuration

### 1. Déployer la Migration SQL

Exécutez la migration dans votre console Supabase SQL Editor :

```bash
# Fichier: supabase/migrations/20260419_freemopay_integration.sql
```

Cette migration crée :
- Table `freemopay_config` : stocke les credentials API
- Table `freemopay_transactions` : historique des transactions
- Politiques RLS appropriées

### 2. Configurer les Credentials Freemopay

Dans Supabase SQL Editor, mettez à jour la configuration avec vos vraies credentials :

```sql
UPDATE freemopay_config
SET
  app_key = 'VOTRE_APP_KEY',
  secret_key = 'VOTRE_SECRET_KEY',
  webhook_url = 'https://VOTRE_PROJECT.supabase.co/functions/v1/freemopay-webhook'
WHERE id = (SELECT id FROM freemopay_config LIMIT 1);
```

**Où trouver vos credentials ?**
- Dashboard Freemopay : https://dashboard.freemopay.com
- Section "API Keys" ou "Développeurs"

### 3. Déployer la Edge Function Webhook

```bash
# Installer Supabase CLI si nécessaire
npm install -g supabase

# Se connecter à votre projet
supabase login
supabase link --project-ref VOTRE_PROJECT_REF

# Déployer la fonction webhook
supabase functions deploy freemopay-webhook

# Vérifier les logs
supabase functions logs freemopay-webhook
```

### 4. Configurer le Webhook dans Freemopay Dashboard

1. Connectez-vous au dashboard Freemopay
2. Allez dans "Webhooks" ou "Callbacks"
3. Ajoutez l'URL : `https://VOTRE_PROJECT.supabase.co/functions/v1/freemopay-webhook`
4. Sauvegardez

### 5. Installer les Dépendances Flutter

```bash
flutter pub get
```

Le package `uuid: ^4.5.1` a déjà été ajouté au `pubspec.yaml`.

## 🧪 Tester l'Intégration

### Test en Mode Sandbox (si disponible)

1. Utilisez les credentials de test Freemopay
2. Testez un dépôt :
   - Montant : 100 FCFA
   - Numéro test : voir docs Freemopay
3. Vérifiez les logs de la Edge Function

### Test en Production

1. **Dépôt** :
   - Ouvrir l'app → Profil → Bouton "Dépôt"
   - Entrer montant (ex: 100 FCFA) et numéro Mobile Money
   - Valider le paiement sur le téléphone
   - Vérifier que les coins sont crédités après validation

2. **Retrait** :
   - Profil → Bouton "Retrait"
   - Entrer montant ≤ solde actuel
   - Vérifier que les coins sont débités immédiatement
   - Vérifier la réception de l'argent sur Mobile Money

## 📊 Monitoring

### Vérifier les Transactions

Dans Supabase SQL Editor :

```sql
-- Voir toutes les transactions Freemopay
SELECT * FROM freemopay_transactions
ORDER BY created_at DESC
LIMIT 20;

-- Voir les transactions en attente
SELECT * FROM freemopay_transactions
WHERE status = 'PENDING';

-- Voir les échecs
SELECT * FROM freemopay_transactions
WHERE status = 'FAILED';
```

### Logs de la Edge Function

```bash
supabase functions logs freemopay-webhook --tail
```

### Vérifier le Wallet

```sql
-- Voir les transactions wallet liées à Freemopay
SELECT * FROM wallet_transactions
WHERE source LIKE 'freemopay%'
ORDER BY created_at DESC;
```

## 🔒 Sécurité

### ✅ Bonnes Pratiques Implémentées

- ✅ Credentials stockés en base de données (pas dans le code)
- ✅ RPC atomiques pour éviter les race conditions
- ✅ Idempotence du webhook (évite les doublons)
- ✅ Validation des numéros de téléphone
- ✅ Vérification du solde avant retrait
- ✅ Re-crédit automatique si retrait échoue

### ⚠️ Points d'Attention

1. **Ne jamais exposer `secret_key` côté client** : uniquement en backend
2. **Webhook accessible publiquement** : normal, c'est voulu
3. **Rate limiting Freemopay** : 100 requêtes/min max
4. **Montants minimaux/maximaux** : à configurer selon besoins

## 🐛 Dépannage

### Problème : Dépôt ne crédite pas les coins

1. Vérifier les logs de la Edge Function
2. Vérifier que le webhook est bien configuré dans Freemopay
3. Vérifier la table `freemopay_transactions` :
   ```sql
   SELECT * FROM freemopay_transactions WHERE reference = 'LA_REFERENCE';
   ```

### Problème : Erreur "Configuration Freemopay manquante"

1. Vérifier que la table `freemopay_config` contient les credentials
2. Vérifier que `is_active = true`

### Problème : Numéro de téléphone invalide

Format attendu : `237XXXXXXXXX` (9 chiffres après 237)
- ✅ `237658895572`
- ✅ `+237658895572`
- ❌ `658895572` (manque indicatif)

### Problème : Retrait débite mais n'envoie pas l'argent

1. Vérifier les logs Freemopay
2. Si échec API Freemopay, les coins sont automatiquement re-crédités
3. Vérifier dans `wallet_transactions` la source `freemopay_withdrawal_failed`

## 📝 Fichiers Créés/Modifiés

### Nouveaux Fichiers

- ✅ `lib/services/freemopay_service.dart` - Service API Freemopay
- ✅ `supabase/migrations/20260419_freemopay_integration.sql` - Schéma DB
- ✅ `supabase/functions/freemopay-webhook/index.ts` - Webhook handler

### Fichiers Modifiés

- ✅ `lib/screens/profile_screen.dart` - Boutons Dépôt/Retrait + dialogs
- ✅ `pubspec.yaml` - Ajout package `uuid`

## 🎯 Fonctionnalités Implémentées

### Dépôt (DEPOSIT)

1. User clique "Dépôt"
2. Entre montant + numéro Mobile Money
3. FreemopayService.initiateDeposit() appelle l'API
4. Transaction enregistrée en BD avec status=PENDING
5. User valide sur son téléphone
6. Freemopay envoie callback au webhook
7. Webhook crédite le wallet via RPC atomique
8. Status mis à jour → SUCCESS

### Retrait (WITHDRAW)

1. User clique "Retrait"
2. Entre montant (≤ solde) + numéro
3. WalletService débite les coins immédiatement
4. FreemopayService.initiateWithdrawal() appelle l'API
5. Si API échoue → re-crédit automatique
6. Transaction enregistrée en BD
7. Freemopay traite le transfert
8. Callback confirme SUCCESS ou FAILED
9. Si FAILED → re-crédit via webhook

## 📚 Ressources

- **API Docs** : Voir `Freemopay api v2.postman_collection (1).json`
- **Dashboard** : http://localhost:5173/dashboard/freemopay (projet dashboard)
- **Support Freemopay** : contact@freemopay.com

---

**Date** : 2026-04-19
**Auteur** : Claude Code
