# Audit cache / Service Worker — Plugbet Web (plugbetx.com)

Date : 2026-05-16 — Audit en lecture seule, aucune modification appliquée.

## TL;DR — Cause probable

**Le problème n'est PAS (plus) côté navigateur ou config : la production
sert un build périmé.** Le serveur nginx de `plugbetx.com` distribue
toujours le build du **14 mai** (avec un **vrai service worker actif du
30 avril**). Les correctifs locaux « Audit A4 » (suppression du SW,
`--pwa-strategy=none`) **n'ont jamais été déployés** sur ce serveur.

Deux populations bloquées, pour deux raisons distinctes :

| Profil utilisateur | Pourquoi il voit l'ancienne version |
|---|---|
| **Nouveau visiteur / sans SW** | Le **serveur lui-même** a des fichiers périmés (écart de déploiement). nginx renvoie bien `no-store`, mais sert de vieux octets. |
| **Visiteur récurrent / SW installé** | Le **service worker du 30 avril** (784 o, bien réel) intercepte les requêtes et sert l'app en cache *avant le réseau*. `no-store` ne contourne PAS un SW déjà installé. Aucun mécanisme de désinscription n'est déployé. |

---

## 1–7. Éléments trouvés vs attendus

| # | Contrôle | Résultat |
|---|---|---|
| 1 | `flutter_service_worker.js` actif ? | 🔴 **OUI en prod** : 784 o, `Last-Modified: 30 Apr 2026`, servi en 200. (Le repo local a un fichier 0 o `--pwa-strategy=none`, mais **non déployé**.) |
| 2 | `index.html` en cache ? | 🟢 nginx envoie `Cache-Control: no-store, must-revalidate`. Mais 🔴 le SW installé le court-circuite pour les récurrents. Live = **7098 o** (vieux, avec script SW) vs local **3687 o** (nettoyé). |
| 3 | `main.dart.js` ancienne version ? | 🔴 **OUI** : live = 5 516 469 o (14 mai) ≠ local `app/` 5 524 496 o ≠ local `build/web` 5 521 315 o. **3 versions divergentes**. |
| 4 | Assets versionnés (hash) ? | 🔴 **NON** : `main.dart.js`, `flutter_bootstrap.js`, `assets/` gardent le même nom à chaque build (Flutter web ne fingerprint pas les noms). Le cache-busting repose donc *entièrement* sur les en-têtes OU le SW — les deux cassés ici. |
| 5 | `manifest.json` | 🟢 Présent (945 o), `no-store` via nginx. Comportement PWA standard, non bloquant. |
| 6 | Navigateur peut garder l'ancien build ? | 🔴 **OUI**, via le SW installé (cache `RESOURCES` cache-first du SW Flutter du 30 avril). |
| 7 | Stratégie PWA active | 🔴 **Incohérente** : prod = PWA avec SW Flutter par défaut (cache-first). Local = `--pwa-strategy=none` (sain) mais **non livré**. |

## 8. En-têtes HTTP (live)

```
/app/index.html      → HTTP 200 · nginx/1.28.3 · Cache-Control: no-store, must-revalidate
                       ETag "6a0632bd-1bba" · Last-Modified Thu 14 May 2026 20:38:21
/app/main.dart.js    → HTTP 200 · Cache-Control: no-store, must-revalidate
                       ETag "6a05c89b-542cb5" · Last-Modified Thu 14 May 2026 13:05:31
/app/flutter_service_worker.js → HTTP 200 · 784 o · Last-Modified Thu 30 Apr 2026
```

- ✅ `Cache-Control: no-store, must-revalidate` correctement positionné par nginx (entry points).
- ⚠️ Pas d'`Expires` ni `Cache-Control` explicite vérifié sur `assets/` / `canvaskit/` / `flutter.js` (à durcir).
- ⚠️ `Last-Modified` / `ETag` présents mais **inopérants face à un SW** (le SW ne revalide pas conditionnellement ses ressources cachées).

## 9. Config serveur

- **Origine = nginx 1.28.3 (Ubuntu) en direct.** Aucun en-tête `Via`,
  `Age`, `X-Cache`, `X-Vercel-*`, `CF-*` → **aucun reverse-proxy /
  cache-proxy / CDN intermédiaire**. Le cache proxy n'est pas le problème.
- **`vercel.json` est INOPÉRANT** : la prod réelle est nginx, pas Vercel.
  Toute la politique de cache configurée dans `vercel.json` ne s'applique
  jamais au site live. (Inspection fine du vhost nginx = via SSH lecture
  seule si tu veux, mais le diagnostic HTTP est déjà concluant.)

## 10. CDN / proxy intermédiaire

🟢 **Aucun.** Réponses directes nginx origin. Pas de version servie par un
edge cache. Le décalage vient du **contenu du serveur d'origine** + du
**SW côté client**, pas d'un intermédiaire.

---

## Risques

1. 🔴 **Gel permanent post-2026-05-21** : le script de l'`index.html`
   déployé contient une IIFE clear-cache qui s'auto-désactive après le
   `DEADLINE = '2026-05-21'` (`if (date >= DEADLINE) return;`). Après
   cette date, les utilisateurs avec l'ancien SW n'ont **plus aucune
   échappatoire** : le vieux SW continue de servir l'app cachée, sans
   logique de désinscription. **Bombe à retardement dans 5 jours.**
2. 🔴 Écart de déploiement durable : le correctif sain (no-SW) existe en
   local mais la prod ne le recevra que par un déploiement nginx explicite.
3. 🟠 3 builds divergents (`build/web`, `app/`, prod) → risque de
   redéployer encore une mauvaise copie.
4. 🟠 Assets non hashés → fragilité structurelle du cache-busting.

---

## Correctif proposé (NON appliqué — à valider)

### Étape 1 — Rebuild propre sans SW
```
cd gost_app_web
flutter build web --release --pwa-strategy=none --base-href /app/
```
Génère un `flutter_service_worker.js` vide + un `index.html` sans SW.

### Étape 2 — `index.html` : ajouter un kill-switch SW SANS deadline
Fichier exact : `gost_app_web/web/index.html` (template source, repris à
chaque build). Insérer, **avant** `flutter_bootstrap.js`, un script qui
désinscrit *inconditionnellement* tout SW résiduel et purge les caches —
**sans `DEADLINE`** (le bug n°1 vient justement de la deadline). Une seule
boucle `reload` protégée par `sessionStorage` pour éviter le rechargement
infini. (Code complet à fournir à l'implémentation.)

### Étape 3 — Déployer sur nginx (la vraie prod)
Copier le contenu de `gost_app_web/build/web/` vers la racine `/app/` du
serveur `plugbetx.com` (chemin exact à confirmer via le vhost nginx —
probablement `/var/www/.../app/`). **C'est l'étape manquante actuelle.**

### Étape 4 — Durcir nginx (config production sûre)
```nginx
# Entrypoints : jamais cachés
location = /app/index.html              { add_header Cache-Control "no-store, must-revalidate" always; }
location = /app/flutter_bootstrap.js    { add_header Cache-Control "no-store, must-revalidate" always; }
location = /app/flutter_service_worker.js { add_header Cache-Control "no-store, must-revalidate" always; }
location = /app/main.dart.js            { add_header Cache-Control "no-store, must-revalidate" always; }
location = /app/version.json            { add_header Cache-Control "no-store, must-revalidate" always; }
location = /app/manifest.json           { add_header Cache-Control "no-store, must-revalidate" always; }
# Assets immuables (canvaskit, fonts) : cache long OK car contenus stables
location ~ ^/app/(canvaskit|assets)/    { add_header Cache-Control "public, max-age=2592000"; }
```

### Étape 5 — Synchroniser les 3 copies
Supprimer `app/` du repo OU automatiser `build/web → app/` pour éliminer
les divergences. Idéalement, ne versionner qu'**une** source de vérité.

### Empêcher définitivement le retour d'anciennes versions
- **no-store** sur les entrypoints (déjà OK côté nginx, à conserver).
- **Pas de service worker** (`--pwa-strategy=none`) — supprime la cause
  racine du gel des récurrents.
- **Kill-switch SW sans deadline** dans l'`index.html` pour évincer les
  SW historiquement installés (sinon ces clients restent figés à vie).
- Optionnel robuste : versionner les assets par querystring
  (`main.dart.js?v=<build_id>`) injecté au build.

---

## Réponse à « ne pas modifier sans identifier la source »

Source identifiée précisément : **(1) déploiement nginx périmé du
14 mai + SW Flutter actif du 30 avril non purgé, (2) le correctif sain
n'a jamais quitté le repo local.** Ce n'est ni le navigateur seul, ni un
CDN, ni `vercel.json`. Action décisive = redéployer le build no-SW sur
nginx **avec** un kill-switch SW sans date limite, avant le 21 mai.
