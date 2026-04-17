# Shorebird Code Push — Setup Guide

Shorebird permet de pousser des mises a jour Dart (UI, logique, bug fixes) sans passer par le Play Store / App Store.

## 1. Installer le CLI (une seule fois)

```powershell
# PowerShell
iwr -useb https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1 | iex
```

```bash
# macOS/Linux
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh | bash
```

Puis :
```bash
shorebird --version   # verifier
shorebird login       # se connecter au compte Shorebird
```

## 2. Initialiser le projet (a la racine de d:\gost_app)

```bash
shorebird init
```

Cette commande :
- Genere `shorebird.yaml` avec un `app_id` unique
- Ajoute `shorebird.yaml` dans la section `assets` de `pubspec.yaml`

**Important** : commit `shorebird.yaml` dans git.

## 3. Creer une release (premier deploiement)

Au lieu de `flutter build apk` / `flutter build appbundle`, utilise :

```bash
shorebird release android            # AAB pour Play Store
shorebird release android --artifact apk  # APK pour distribution directe
```

Upload ensuite l'AAB/APK sur le Play Store ou distribue l'APK.
Chaque release Shorebird est versionnee (ex: `1.0.0+1`).

## 4. Pousser un patch OTA

Apres modification du code Dart :

```bash
shorebird patch android
```

Le CLI :
1. Compile le diff
2. L'upload sur les serveurs Shorebird
3. Les utilisateurs recoivent le patch au prochain lancement de l'app

**Limites** :
- Seul le code Dart est patchable (UI, logique)
- Ajout de nouveaux assets natifs, permissions Android, plugins natifs → nouvelle release obligatoire
- Version du patch doit matcher la release deployee

## 5. Verifier l'etat

```bash
shorebird releases list
shorebird patches list
```

## 6. Integration in-app (deja en place)

Le service `lib/services/shorebird_service.dart` est deja cable dans `main.dart` :
- Au demarrage, verifie et telecharge silencieusement un patch dispo
- Le patch est applique au prochain lancement

Pas de bouton "Update now" visible — l'utilisateur ne voit rien, le patch arrive de maniere transparente.

## 7. Workflow typique

```bash
# Jour J : nouveau build
shorebird release android --artifact apk
# → upload APK, version 1.0.1

# Jour J+2 : bug fix
# ... edit code ...
shorebird patch android
# → les users recoivent le fix au prochain lancement

# Jour J+10 : nouvelle fonctionnalite avec nouveau plugin natif
shorebird release android --artifact apk
# → version 1.0.2, re-upload APK
```

## 8. Debug

- `debug` mode : Shorebird est desactive, le service log "indisponible"
- `release` mode avec `flutter build` : Shorebird est desactive
- `release` mode avec `shorebird release` : Shorebird est actif
