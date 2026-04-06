# CORA DICE - Jeu de dés camerounais virtuel 🎲

## Description

Cora Dice est une implémentation virtuelle (100% coins, pas d'argent réel) du jeu de dés camerounais populaire. Le jeu se joue de 2 à 6 joueurs en temps réel avec Supabase.

### Règles du jeu

- **Mise fixe** : 200 coins par joueur (pot = mise × nb_joueurs)
- **CORA (1+1)** : Gagne **DOUBLE POT** et la partie s'arrête immédiatement
- **Plusieurs Cora** : Partie annulée, remboursement total
- **7** : Perd automatiquement (score effectif = -1)
- **Plus haut total** : Gagne le pot normal
- **Égalité** : Partie annulée, remboursement

## Structure du projet

```
lib/games/cora_dice/
├── models/
│   └── cora_models.dart          # Modèles de données
├── services/
│   └── cora_service.dart         # Service Supabase + logique
├── screens/
│   ├── cora_dice_screen.dart     # Écran principal (liste)
│   ├── create_room_screen.dart   # Création de partie
│   ├── lobby_screen.dart         # Salle d'attente
│   └── game_screen.dart          # Partie en cours
├── components/
│   └── dice_animation.dart       # Composant dés animés
└── README.md                     # Ce fichier
```

## Installation

### 1. Migration Supabase

Exécutez la migration SQL dans votre dashboard Supabase :

```bash
# Fichier : supabase_migrations/05_cora_dice.sql
```

Cette migration crée :
- `cora_rooms` : Salles d'attente
- `cora_games` : Parties en cours
- `cora_room_players` : Joueurs dans les salles
- `cora_messages` : Chat en lobby
- Fonctions RPC : `create_cora_room`, `join_cora_room`, `toggle_cora_ready`, `submit_cora_roll`
- Policies RLS pour la sécurité

### 2. Intégration dans la navigation

Dans `lib/main.dart`, ajoutez Cora Dice à votre bottom navigation :

```dart
import 'games/cora_dice/screens/cora_dice_screen.dart';

// Dans votre StatefulWidget principal
class _MainAppState extends State<MainApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    FavoritesScreen(),
    LudoTabScreen(),
    CoraDiceScreen(), // ← Ajoutez ici
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Matchs'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favoris'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'Ludo'),
          BottomNavigationBarItem(icon: Icon(Icons.casino), label: 'Cora'), // ← Ajoutez ici
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}
```

**OU** ajoutez un onglet "Jeux" avec une liste de jeux :

```dart
// Créer un écran GamesScreen avec une liste
class GamesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _gameCard(
          context,
          'Ludo',
          'Jeu de plateau classique',
          Icons.grid_4x4,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => LudoTabScreen())),
        ),
        _gameCard(
          context,
          'Cora Dice',
          'Jeu de dés camerounais',
          Icons.casino,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoraDiceScreen())),
        ),
      ],
    );
  }
}
```

### 3. Dépendances (déjà installées)

Vérifiez dans `pubspec.yaml` :

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.0.0
  # Autres dépendances existantes...
```

## Utilisation

### Créer une partie

1. Ouvrez l'écran Cora Dice
2. Appuyez sur **"Créer"**
3. Choisissez le nombre de joueurs (2-6)
4. Choisissez Public (visible à tous) ou Privé (code à partager)
5. Créez la partie → Code généré automatiquement

### Rejoindre une partie

**Option 1 : Parties publiques**
- Scrollez la liste des parties publiques
- Appuyez sur **"Join"** sur une partie

**Option 2 : Par code**
- Appuyez sur **"Rejoindre"**
- Entrez le code à 6 caractères (ex: A3F8D2)
- Rejoignez la salle d'attente

### Dans le lobby

1. Les joueurs apparaissent dans une grille
2. Utilisez le chat pour communiquer
3. Quand tous les joueurs sont prêts, appuyez sur **"PRÊT !"**
4. La partie démarre automatiquement quand tous sont prêts

### Pendant la partie

1. Chaque joueur lance les dés à son tour
2. Appuyez sur **"LANCER LES DÉS"** quand c'est votre tour
3. Animations :
   - **Cora (1+1)** : Explosion verte + texte "CORA!"
   - **7** : Tremblement rouge (perd auto)
   - **Autres** : Affichage du total
4. Résultat affiché à la fin avec gains/pertes

## Test en local

### Tester avec 2 appareils

1. **Appareil 1** : Créez une partie publique avec 2 joueurs
2. **Appareil 2** : Rejoignez la partie depuis la liste
3. Les deux passent en **Prêt**
4. Lancez les dés tour par tour

### Tester en solo (simuler 2 joueurs)

1. Créez une partie privée avec 2 joueurs
2. Notez le code
3. Dans un navigateur web, ouvrez Supabase Dashboard
4. Allez dans **Table Editor** → `cora_room_players`
5. Insérez manuellement un 2ème joueur :
   ```sql
   INSERT INTO cora_room_players (room_id, user_id, username, is_ready)
   VALUES ('votre_room_id', 'fake_user_id', 'TestBot', true);
   ```
6. Dans l'app, passez en **Prêt**
7. La partie démarre !

### Tester les règles

**Cas 1 : Cora gagne**
- Joueur 1 : lance et obtient 1+1 (Cora)
- ✅ Résultat : Joueur 1 gagne **double pot**

**Cas 2 : 7 perd**
- Joueur 1 : lance et obtient 4+3 (7)
- Joueur 2 : lance et obtient 2+2 (4)
- ✅ Résultat : Joueur 2 gagne (Joueur 1 a score -1)

**Cas 3 : Plus haut gagne**
- Joueur 1 : 3+5 = 8
- Joueur 2 : 6+4 = 10
- ✅ Résultat : Joueur 2 gagne le pot

**Cas 4 : Égalité**
- Joueur 1 : 5+3 = 8
- Joueur 2 : 4+4 = 8
- ✅ Résultat : Partie annulée, remboursement

**Cas 5 : Plusieurs Cora**
- Joueur 1 : 1+1 (Cora)
- Joueur 2 : 1+1 (Cora)
- ✅ Résultat : Partie annulée, remboursement

## Architecture technique

### Realtime avec Supabase

Le jeu utilise **Supabase Realtime** pour la synchronisation :

```dart
// Écoute des changements de partie
_gameChannel = _service.subscribeGame(gameId, (game) {
  setState(() => _game = game);
  // Mise à jour automatique de l'UI
});
```

### Sécurité (RLS)

Toutes les tables utilisent **Row Level Security** :
- Les joueurs ne voient que leurs parties
- Impossible de tricher (lancers validés côté serveur)
- Chat limité aux participants

### Gestion des coins

**IMPORTANT** : Les coins sont gérés localement pour le moment. Pour une version production :

1. Ajoutez une colonne `coins` à `user_profiles`
2. Créez des fonctions Supabase pour débiter/créditer :
   ```sql
   CREATE FUNCTION debit_coins(user_id uuid, amount int) ...
   CREATE FUNCTION credit_coins(user_id uuid, amount int) ...
   ```
3. Appelez ces fonctions dans `create_cora_room` et `submit_cora_roll`

## Personnalisation

### Changer la mise

Dans `create_room_screen.dart` :

```dart
betAmount: 200, // ← Changez ici ou ajoutez un slider
```

### Ajouter des sons

1. Ajoutez les fichiers MP3 dans `assets/sounds/cora/`
2. Installez `audioplayers` ou `flame_audio`
3. Dans `game_screen.dart` :

```dart
import 'package:audioplayers/audioplayers.dart';

final _audioPlayer = AudioPlayer();

void _playSound(String sound) {
  _audioPlayer.play(AssetSource('sounds/cora/$sound.mp3'));
}

// Lors du lancer
_playSound('dice_roll');

// Si Cora
if (roll.isCora) {
  _playSound('cora_win');
}
```

### Ajouter des vibrations

Dans `game_screen.dart` :

```dart
import 'package:flutter/services.dart';

// Déjà implémenté :
HapticFeedback.heavyImpact(); // Cora
HapticFeedback.mediumImpact(); // 7
HapticFeedback.lightImpact(); // Normal
```

## Dépannage

### Erreur : "Table cora_rooms doesn't exist"
→ Exécutez la migration SQL `05_cora_dice.sql`

### Erreur : "Function create_cora_room doesn't exist"
→ Vérifiez que toutes les fonctions SQL sont créées

### Les dés ne s'animent pas
→ Vérifiez que `AnimationController` est bien initialisé avec `vsync: this`

### La partie ne démarre pas
→ Vérifiez que tous les joueurs sont marqués `is_ready = true`

### Le chat ne fonctionne pas
→ Vérifiez que la table `cora_messages` a le realtime activé

## Améliorations futures

- [ ] Sons (dice_roll.mp3, cora_win.mp3, lose.mp3)
- [ ] Confettis avec `confetti` package sur victoire
- [ ] Historique des parties
- [ ] Classement / Leaderboard
- [ ] Animations 3D avec Rive pour les dés
- [ ] Mode tournoi
- [ ] Système de niveau/badges
- [ ] Invitations push notifications

## Licence

Ce jeu est créé pour un usage personnel/éducatif. Aucun argent réel n'est impliqué.

---

**Bon jeu ! 🎲🎉**
