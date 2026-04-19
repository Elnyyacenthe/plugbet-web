# 🚀 Setup Rapide Freemopay

## ✅ Étapes à Suivre

### 1️⃣ Créer la table `freemopay_transactions` dans Supabase

1. Allez sur https://supabase.com/dashboard
2. Sélectionnez votre projet `dqzrociaaztlezwlgzwh`
3. Cliquez sur **SQL Editor** dans le menu de gauche
4. Copiez-collez tout le contenu du fichier **`EXECUTE_THIS_SQL.sql`**
5. Cliquez sur **Run** (ou Ctrl+Enter)

### 2️⃣ Vérifier la configuration Freemopay

La configuration existe déjà dans la table `app_settings` avec la clé `freemopay_config`.

Vérifiez qu'elle est active :

```sql
SELECT
  key,
  value->>'active' as is_active,
  value->>'appKey' as app_key_preview,
  value->>'callbackUrl' as callback_url
FROM app_settings
WHERE key = 'freemopay_config';
```

Si `is_active` = `false`, activez-la dans le dashboard :
- http://localhost:5173/dashboard/freemopay
- Cochez "Service actif"
- Sauvegardez

### 3️⃣ Tester l'Application Mobile

1. Hot reload l'app Flutter (touche `R` dans le terminal)
2. Allez dans **Profil**
3. Vous devriez voir les boutons **"Dépôt"** et **"Retrait"**
4. Essayez un dépôt test :
   - Montant : 100 FCFA
   - Numéro : 237658895572 (remplacez par le vôtre)

### 4️⃣ Déployer le Webhook (Optionnel pour l'instant)

Le webhook permet de créditer automatiquement le wallet après validation du paiement.

```bash
# Installer Supabase CLI
npm install -g supabase

# Se connecter
supabase login

# Lier le projet
supabase link --project-ref dqzrociaaztlezwlgzwh

# Déployer la fonction
supabase functions deploy freemopay-webhook

# Vérifier les logs
supabase functions logs freemopay-webhook --tail
```

Ensuite, configurez l'URL webhook dans Freemopay dashboard :
```
https://dqzrociaaztlezwlgzwh.supabase.co/functions/v1/freemopay-webhook
```

## 📊 Vérifier que Tout Fonctionne

### Dans les logs de l'app Flutter :

✅ Succès :
```
ℹ  [FREEMOPAY] Freemopay config loaded successfully
```

❌ Erreur (si la table n'existe pas) :
```
❌ [FREEMOPAY] loadConfig
   └─ PostgrestException: Could not find the table 'freemopay_transactions'
```

### Dans Supabase :

```sql
-- Voir les transactions créées
SELECT * FROM freemopay_transactions
ORDER BY created_at DESC;
```

## 🎯 Test Complet Dépôt

1. **App mobile** : Cliquez sur "Dépôt" → Entrez 100 FCFA et votre numéro
2. **Freemopay** : Vous recevez une notification sur votre téléphone → Validez
3. **Webhook** : Le callback crédite automatiquement 100 coins
4. **Vérification** : Votre solde passe de X à X+100 coins

## 🐛 Problèmes Courants

### Erreur : "Table 'freemopay_transactions' not found"
➡️ Exécutez le fichier `EXECUTE_THIS_SQL.sql` dans Supabase SQL Editor

### Erreur : "No Freemopay config found"
➡️ Activez le service dans le dashboard : http://localhost:5173/dashboard/freemopay

### Erreur : "Freemopay service is disabled"
➡️ Même solution, cochez "Service actif" dans le dashboard

### Les coins ne sont pas crédités après paiement
➡️ Le webhook n'est pas encore déployé. Pour l'instant, c'est normal. Déployez-le (étape 4)

---

**Vous êtes prêt !** 🎉

Testez maintenant un dépôt depuis l'app mobile.
