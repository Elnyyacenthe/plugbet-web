# Setup — Push notifications de maintenance Plugbet

Cette Edge Function envoie une notification FCM v1 à tous les appareils
enregistrés dans `push_tokens` quand une annonce est créée dans
`app_announcements`. Cela fonctionne sur **toutes les versions** de l'app
mobile installées (le push transite par Firebase, pas par le code client).

## Étapes (à faire **une seule fois**)

### 1. Récupérer le Service Account Firebase

1. Aller sur https://console.firebase.google.com/
2. Sélectionner le projet Plugbet
3. ⚙️ **Project Settings** → onglet **Service accounts**
4. Cliquer **Generate new private key** → télécharger le JSON
5. Ouvrir le fichier JSON, copier **tout le contenu**

### 2. Configurer le secret dans Supabase

Dans le terminal local (avec Supabase CLI installé) :

```bash
cd D:\gost_app
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat /chemin/vers/firebase-key.json)"
```

Ou via le Dashboard Supabase :
- **Edge Functions** → **Manage secrets** → ajouter `FIREBASE_SERVICE_ACCOUNT`
  avec **tout le JSON** comme valeur (incluant `{` et `}`)

### 3. Déployer la fonction

```bash
cd D:\gost_app
supabase functions deploy send-announcement-push
```

→ Note l'URL qu'elle te retourne, format :
`https://xxxxxxxxxxxx.supabase.co/functions/v1/send-announcement-push`

### 4. Configurer l'auto-trigger côté DB

Dans Supabase SQL Editor, exécuter d'abord
`supabase_announcements_push_trigger.sql` (du repo `dashboard_gost_app`).

Puis insérer la config (remplacer les 2 valeurs) :

```sql
-- Récupérer ton project_ref Supabase : Dashboard > Settings > General
-- Récupérer ta service_role_key  : Dashboard > Settings > API
INSERT INTO app_settings (key, value)
VALUES (
  'announcement_push_config',
  jsonb_build_object(
    'function_url', 'https://VOTRE_PROJECT_REF.supabase.co/functions/v1/send-announcement-push',
    'service_role_key', 'eyJxxxxxx_LA_SERVICE_ROLE_KEY'
  )
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

### 5. Tester

Dans le dashboard `/dashboard/announcements`, envoyer une annonce.
**Tous les appareils avec un token FCM enregistré** doivent recevoir la
notification système — peu importe la version de l'app installée.

Si un appareil ne reçoit rien :
- Vérifier qu'il a un token : `SELECT COUNT(*) FROM push_tokens WHERE user_id = 'USER_ID';`
- Vérifier les logs de l'Edge Function : Supabase Dashboard → Functions → Logs
- Cas typique : token expiré → la fonction le supprime automatiquement.
  L'utilisateur doit rouvrir l'app pour ré-enregistrer.

## Architecture

```
[Admin] → Dashboard /announcements
            ↓ (broadcast_announcement RPC)
        app_announcements (INSERT)
            ↓ (trigger app_announcements_push_trg)
        pg_net.http_post → Edge Function send-announcement-push
            ↓
        Lit push_tokens, signe JWT Firebase, POST FCM v1
            ↓
        FCM push → tous les téléphones (Android & iOS)
```

## Re-broadcast manuel

Si vous voulez ré-envoyer une annonce existante (cas où FCM avait
échoué) :

```sql
SELECT resend_announcement_push('ID_DE_L_ANNONCE'::uuid);
```
