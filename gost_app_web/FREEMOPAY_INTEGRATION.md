# Intégration Freemopay - Dépôt et Retrait d'Argent

## 📋 Contexte

Ce document décrit l'intégration du système de paiement **Freemopay v2** pour permettre aux utilisateurs de **déposer** et **retirer** de l'argent via Mobile Money/Orange Money depuis l'écran profil.

### Conversion
- **1 FCFA = 1 coin**
- Après un dépôt réussi → ajouter des coins au wallet
- Avant un retrait → déduire les coins du wallet

---

## 🔑 API Freemopay v2

### Base URL
```
https://api-v2.freemopay.com/api/v2
```

### Authentification
Deux méthodes disponibles :
1. **Basic Auth** : `username=appKey`, `password=secretKey`
2. **Bearer Token** : JWT obtenu via `/payment/token` (expire en 3600s)

### Endpoints principaux

#### 1. Générer un token (optionnel)
```http
POST /payment/token
Content-Type: application/json

{
  "appKey": "<string>",
  "secretKey": "<string>"
}
```

**Réponse (200 OK)** :
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 3600
}
```

#### 2. Initier un dépôt (DEPOSIT)
```http
POST /payment
Authorization: Basic base64(appKey:secretKey)
Content-Type: application/json

{
  "payer": "237658895572",
  "amount": "100",
  "externalId": "unique-transaction-id",
  "description": "Depot de coins",
  "callback": "https://votre-webhook.com/freemopay/callback"
}
```

**Réponse (200 OK)** :
```json
{
  "reference": "cecb550c-f542-4f63-abe6-40534a02ddf1",
  "status": "SUCCESS",
  "message": "Paiement initié avec success"
}
```

**Statuts** :
- `PENDING` : En attente de validation du payeur
- `SUCCESS` : Paiement confirmé (via callback)
- `FAILED` : Paiement échoué

#### 3. Initier un retrait (WITHDRAW)
```http
POST /payment/direct-withdraw
Authorization: Basic base64(appKey:secretKey)
Content-Type: application/json

{
  "receiver": "237695509408",
  "amount": "100",
  "externalId": "unique-transaction-id",
  "callback": "https://votre-webhook.com/freemopay/callback"
}
```

**Réponse (200 OK)** :
```json
{
  "reference": "0e8d2768-e3fd-4224-b76f-3f7ae7bf9d27",
  "status": "CREATED",
  "message": "cashout created"
}
```

#### 4. Vérifier le statut d'une transaction
```http
GET /payment/:reference
Authorization: Basic base64(appKey:secretKey)
```

**Réponse (200 OK)** :
```json
{
  "reference": "cecb550c-f542-4f63-abe6-40534a02ddf1",
  "merchandRef": "unique-transaction-id",
  "amount": 100,
  "status": "SUCCESS",
  "reason": "Paiement confirmé"
}
```

### Webhook Callback

Freemopay envoie un POST au webhook configuré quand la transaction est finalisée :

```json
{
  "status": "SUCCESS",
  "reference": "cecb550c-f542-4f63-abe6-40534a02ddf1",
  "amount": 100,
  "transactionType": "DEPOSIT",
  "externalId": "unique-transaction-id",
  "message": "Paiement confirmé"
}
```

**Statuts possibles** :
- `SUCCESS` : Transaction réussie
- `FAILED` : Transaction échouée (avec `reason`)

---

## 💾 Configuration Supabase

Les credentials Freemopay sont stockés dans Supabase :
- **Dashboard** : http://localhost:5173/dashboard/freemopay
- **Champs** :
  - `appKey` : Clé publique
  - `secretKey` : Clé secrète

**TODO** : Créer une table `freemopay_config` ou stocker dans `app_config` :
```sql
CREATE TABLE IF NOT EXISTS freemopay_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_key TEXT NOT NULL,
  secret_key TEXT NOT NULL,
  webhook_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 🎯 Architecture Wallet Existante

### WalletProvider (`lib/providers/wallet_provider.dart`)
- Gère le solde global (`coins`) en temps réel
- S'abonne aux changements Supabase (Realtime)
- Méthodes :
  - `refresh()` : Recharge le solde
  - `updateLocal(int newCoins)` : Met à jour localement

### WalletService (`lib/services/wallet_service.dart`)
- Opérations atomiques via RPC `my_wallet_apply_delta`
- Méthodes :
  - `addCoins(amount, {source, referenceId, note})` : Crédit
  - `deductCoins(amount, {source, referenceId, note})` : Débit (vérifie solde)
  - Chaque opération crée une entrée dans `wallet_transactions` (audit trail)

**Sources possibles** :
- `'freemopay_deposit'` : Dépôt via Freemopay
- `'freemopay_withdrawal'` : Retrait via Freemopay

---

## 📝 Plan d'Implémentation

### 1. Créer le service Freemopay

**Fichier** : `lib/services/freemopay_service.dart`

```dart
class FreemopayService {
  static const _baseUrl = 'https://api-v2.freemopay.com/api/v2';

  // Config (à charger depuis Supabase)
  String? _appKey;
  String? _secretKey;

  // Méthodes :
  Future<void> loadConfig(); // Charge depuis Supabase
  Future<Map<String, dynamic>> initiateDeposit({
    required String payer,
    required int amount,
    required String externalId,
  });
  Future<Map<String, dynamic>> initiateWithdrawal({
    required String receiver,
    required int amount,
    required String externalId,
  });
  Future<Map<String, dynamic>> getTransactionStatus(String reference);
}
```

### 2. Modifier `profile_screen.dart`

**Emplacement** : Après la section "Solde" (ligne ~395)

Ajouter deux boutons :
```dart
Row(
  children: [
    Expanded(
      child: _buildActionButton(
        label: 'Dépôt',
        icon: Icons.add_circle_outline,
        color: AppColors.neonGreen,
        onTap: _showDepositDialog,
      ),
    ),
    SizedBox(width: 12),
    Expanded(
      child: _buildActionButton(
        label: 'Retrait',
        icon: Icons.remove_circle_outline,
        color: AppColors.neonOrange,
        onTap: _showWithdrawalDialog,
      ),
    ),
  ],
)
```

### 3. Créer les dialogs

**Dialog Dépôt** :
- Champs : Montant (int), Numéro Mobile Money (string)
- Validation : montant > 0, numéro valide (237XXXXXXXXX)
- Action : `FreemopayService.initiateDeposit()`
- Feedback : "Transaction en attente. Validez sur votre téléphone."

**Dialog Retrait** :
- Champs : Montant (int), Numéro de réception (string)
- Validation : montant > 0, montant <= solde actuel, numéro valide
- Action :
  1. `WalletService.deductCoins(amount, source: 'freemopay_withdrawal')`
  2. Si succès → `FreemopayService.initiateWithdrawal()`
  3. Si échec API → Re-créditer les coins

### 4. Gérer le Webhook Callback

**Option A : Supabase Edge Function**

Créer une fonction `freemopay-webhook` :
```typescript
// supabase/functions/freemopay-webhook/index.ts
Deno.serve(async (req) => {
  const payload = await req.json();
  const { status, reference, amount, transactionType, externalId } = payload;

  if (status === 'SUCCESS') {
    if (transactionType === 'DEPOSIT') {
      // Créditer le wallet via RPC
      await supabaseAdmin.rpc('my_wallet_apply_delta', {
        p_user_id: extractUserIdFromExternalId(externalId),
        p_delta: amount,
        p_source: 'freemopay_deposit',
        p_reference_id: reference,
      });
    }
    // Enregistrer dans une table freemopay_transactions
  }

  return new Response(JSON.stringify({ success: true }), { status: 200 });
});
```

**Option B : Polling côté client**

Si pas de webhook :
- Après `initiateDeposit()`, récupérer la `reference`
- Polling toutes les 5s : `getTransactionStatus(reference)`
- Si `SUCCESS` → `WalletService.addCoins()`

### 5. Table Supabase pour l'historique

```sql
CREATE TABLE IF NOT EXISTS freemopay_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  reference TEXT UNIQUE NOT NULL,
  external_id TEXT NOT NULL,
  transaction_type TEXT NOT NULL, -- 'DEPOSIT' ou 'WITHDRAW'
  amount INT NOT NULL,
  status TEXT NOT NULL, -- 'PENDING', 'SUCCESS', 'FAILED'
  payer_or_receiver TEXT,
  message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_freemopay_user ON freemopay_transactions(user_id);
CREATE INDEX idx_freemopay_reference ON freemopay_transactions(reference);
```

### 6. Afficher dans l'historique

Modifier `_buildHistoryTab()` dans `profile_screen.dart` :
- Charger les transactions Freemopay depuis `freemopay_transactions`
- Ajouter à la liste `_transactions`
- Type : `'deposit'` ou `'withdrawal'`

---

## 🔒 Sécurité

1. **Ne jamais exposer `secretKey` côté client** : stocker uniquement en backend
2. **Validation des webhooks** : vérifier la signature si Freemopay la fournit
3. **Éviter les race conditions** : utiliser RPC atomiques (`my_wallet_apply_delta`)
4. **Limiter les montants** : min/max par transaction
5. **Rate limiting** : 100 requêtes/min (Freemopay)

---

## 📂 Fichiers à Créer/Modifier

### Nouveaux fichiers
- [ ] `lib/services/freemopay_service.dart`
- [ ] `supabase/functions/freemopay-webhook/index.ts` (si webhook)
- [ ] Migration SQL pour `freemopay_config` et `freemopay_transactions`

### Fichiers à modifier
- [ ] `lib/screens/profile_screen.dart` : Ajouter boutons Dépôt/Retrait + dialogs
- [ ] `lib/services/wallet_service.dart` : Possiblement ajouter des sources spécifiques

### Configuration
- [ ] Ajouter les credentials dans Supabase (table `freemopay_config`)
- [ ] Configurer le webhook URL dans Freemopay dashboard

---

## 🧪 Tests à Effectuer

1. **Dépôt réussi** :
   - Montant crédité dans le wallet
   - Transaction visible dans l'historique
   - Statut mis à jour après callback

2. **Dépôt échoué** :
   - Aucun crédit dans le wallet
   - Message d'erreur affiché

3. **Retrait réussi** :
   - Montant débité avant l'appel API
   - Argent reçu sur Mobile Money
   - Transaction visible dans l'historique

4. **Retrait échoué** :
   - Coins re-crédités si API échoue
   - Message d'erreur affiché

5. **Cas limites** :
   - Solde insuffisant pour retrait
   - Numéro invalide
   - Timeout API
   - Webhook en double (idempotence)

---

## 📚 Références

- **API Docs** : `/Users/macbookpro/Desktop/Developments/Personnals/dashboard_gost_app/Freemopay api v2.postman_collection (1).json`
- **Dashboard Freemopay** : http://localhost:5173/dashboard/freemopay
- **Profile Screen** : `/Users/macbookpro/Desktop/Developments/Personnals/gost_app/lib/screens/profile_screen.dart`
- **Wallet Provider** : `/Users/macbookpro/Desktop/Developments/Personnals/gost_app/lib/providers/wallet_provider.dart`
- **Wallet Service** : `/Users/macbookpro/Desktop/Developments/Personnals/gost_app/lib/services/wallet_service.dart`

---

## 🚀 Prochaines Étapes

1. Créer `FreemopayService` avec auth Basic
2. Ajouter les boutons dans `profile_screen.dart`
3. Implémenter les dialogs (montant + numéro)
4. Tester le flux dépôt en mode Sandbox (si disponible)
5. Créer la Edge Function webhook
6. Tester le flux complet en production

---

**Date** : 2026-04-18
**Auteur** : Claude Code
