# Nkoulou Live Score – Guide d'installation complet

## 1. Prérequis

- Flutter 3.24+ installé (`flutter doctor`)
- Un appareil/émulateur Android ou iOS
- Connexion internet pour l'API

## 2. Obtenir la clé API football-data.org

1. Aller sur **https://www.football-data.org/**
2. Cliquer **"Register"** (gratuit, aucune carte bancaire)
3. Remplir le formulaire et confirmer l'email
4. La clé API apparaît dans le **Dashboard**
5. Ouvrir `lib/services/api_football_service.dart`
6. Remplacer `VOTRE_CLE_API_ICI` par votre clé

### Limites du plan gratuit :
- 10 requêtes par minute
- Compétitions : Premier League, La Liga, Bundesliga, Serie A, Ligue 1, Champions League, Euro, Coupe du Monde

## 3. Configurer Supabase (optionnel mais recommandé)

1. Créer un compte sur **https://supabase.com** (plan gratuit)
2. Créer un nouveau projet (noter l'URL et la clé anon)
3. Ouvrir **SQL Editor** et exécuter :

```sql
-- Table des matchs (pour le realtime)
create table public.matches (
  id bigint primary key,
  competition_id int,
  competition_name text,
  home_team_id int,
  home_team_name text,
  away_team_id int,
  away_team_name text,
  home_score int default 0,
  away_score int default 0,
  status text default 'SCHEDULED',
  minute int,
  utc_date timestamptz,
  events jsonb default '[]'::jsonb,
  updated_at timestamptz default now()
);

-- Activer le Realtime
alter publication supabase_realtime add table public.matches;

-- Table des favoris utilisateurs
create table public.user_favorites (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade,
  team_id int not null,
  created_at timestamptz default now(),
  unique(user_id, team_id)
);

-- Row Level Security
alter table public.user_favorites enable row level security;
create policy "Users can manage their own favorites"
  on public.user_favorites for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.matches enable row level security;
create policy "Anyone can read matches"
  on public.matches for select using (true);
```

4. Ouvrir `lib/services/supabase_service.dart`
5. Remplacer `VOTRE_PROJET` et `VOTRE_CLE_ANON_ICI`

> **Sans Supabase** : L'app fonctionne quand même ! Les favoris seront
> stockés localement via Hive, sans sync multi-device ni realtime.

## 4. Installer les dépendances

```bash
cd gost_app
flutter pub get
```

## 5. Lancer l'application

```bash
# Android
flutter run

# iOS (macOS uniquement)
cd ios && pod install && cd ..
flutter run

# Web (debug)
flutter run -d chrome
```

## 6. Créer l'icône de l'app

Placez une image PNG 1024x1024 dans `assets/icon/app_icon.png` puis :

```bash
dart run flutter_launcher_icons
```

## 7. Architecture du polling intelligent

```
App au premier plan :
  ├── Matchs LIVE détectés → polling toutes les 30s (API /matches?status=LIVE)
  ├── Pas de matchs LIVE   → pas de polling rapide
  └── Tous les matchs      → polling toutes les 120s (API /matches)

App en arrière-plan :
  └── Polling désactivé (économie batterie)

App revient au premier plan :
  └── Rafraîchissement immédiat
```

## 8. Structure des fichiers

```
lib/
├── main.dart                         # Point d'entrée, init
├── theme/
│   └── app_theme.dart                # Couleurs, gradients, thème
├── models/
│   ├── football_models.dart          # Match, Team, Event, Score...
│   └── football_models.g.dart        # Adaptateurs Hive
├── services/
│   ├── api_football_service.dart     # API football-data.org
│   ├── hive_service.dart             # Cache local + favoris
│   └── supabase_service.dart         # Auth + Realtime + DB
├── providers/
│   ├── matches_provider.dart         # État global des matchs + polling
│   └── favorites_provider.dart       # Gestion des favoris
├── screens/
│   ├── home_screen.dart              # Accueil (carousel + liste)
│   ├── match_detail_screen.dart      # Détail (timeline + stats)
│   ├── favorites_screen.dart         # Matchs favoris
│   ├── search_screen.dart            # Recherche équipes
│   └── settings_screen.dart          # Paramètres + auth
└── widgets/
    ├── carousel_card.dart            # Card grand format carousel
    ├── match_card.dart               # Card match liste
    ├── score_display.dart            # Score animé + badge statut
    ├── team_crest.dart               # Logo équipe avec fallback
    ├── event_tile.dart               # Événement timeline
    ├── stat_bar.dart                 # Barre de stat
    └── loading_shimmer.dart          # Shimmer de chargement
```

## 9. Gestion des erreurs

| Situation | Comportement |
|---|---|
| Pas de connexion | Charge les matchs depuis le cache Hive |
| API rate limit (429) | Attend 30s puis réessaye une fois |
| Supabase non configuré | App fonctionne en mode local uniquement |
| Clé API invalide | Affiche l'écran d'erreur avec bouton "Réessayer" |
| Aucun match aujourd'hui | Affiche un état vide élégant |

## 10. Build production

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# iOS (macOS uniquement)
flutter build ios --release
```
