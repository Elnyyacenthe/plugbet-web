# 🎲 CORA DICE - Guide d'intégration complet

## ✅ Fichiers créés

Tous les fichiers suivants ont été générés et sont prêts à l'emploi :

### Backend (Supabase)
- ✅ `supabase_migrations/05_cora_dice.sql` - Migration complète (tables, RLS, fonctions)

### Modèles
- ✅ `lib/games/cora_dice/models/cora_models.dart` - Modèles de données complets

### Services
- ✅ `lib/games/cora_dice/services/cora_service.dart` - Service Supabase + logique métier

### Écrans
- ✅ `lib/games/cora_dice/screens/cora_dice_screen.dart` - Écran principal (liste)
- ✅ `lib/games/cora_dice/screens/create_room_screen.dart` - Création de partie
- ✅ `lib/games/cora_dice/screens/lobby_screen.dart` - Salle d'attente + chat
- ✅ `lib/games/cora_dice/screens/game_screen.dart` - Jeu en cours

### Composants
- ✅ `lib/games/cora_dice/components/dice_animation.dart` - Dés animés

### Documentation
- ✅ `lib/games/cora_dice/README.md` - Documentation complète

---

## 🚀 ÉTAPES D'INSTALLATION (5 minutes)

### 1️⃣ Exécuter la migration SQL Supabase

1. Ouvrez votre **Supabase Dashboard**
2. Allez dans **SQL Editor**
3. Collez le contenu de `supabase_migrations/05_cora_dice.sql`
4. Cliquez sur **Run**
5. ✅ Vérifiez que les tables sont créées dans **Table Editor**

### 2️⃣ Intégrer dans la navigation

**Option A : Ajouter un onglet "Cora" dans la bottom navigation**

Éditez `lib/main.dart` :

```dart
import 'games/cora_dice/screens/cora_dice_screen.dart';

// Dans votre widget principal
class _MainAppState extends State<MainApp> {
  final Map<int, Widget> _cachedScreens = {};
  int _currentIndex = 0;

  Widget _buildScreen(int index) {
    return _cachedScreens.putIfAbsent(index, () {
      switch (index) {
        case 0: return HomeScreen(scaffoldKey: _scaffoldKey);
        case 1: return const FavoritesScreen();
        case 2: return const LudoTabScreen();
        case 3: return const CoraDiceScreen(); // ← AJOUTEZ ICI
        case 4: return SettingsScreen(...);
        default: return const SizedBox();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreen(_currentIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.bgBlueNight,
        selectedItemColor: AppColors.neonGreen,
        unselectedItemColor: AppColors.textMuted,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Matchs'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favoris'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'Ludo'),
          BottomNavigationBarItem(icon: Icon(Icons.casino), label: 'Cora'), // ← AJOUTEZ ICI
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}
```

**Option B : Créer un écran "Jeux" avec une liste**

Créez `lib/screens/games_screen.dart` :

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../ludo/screens/ludo_tab_screen.dart';
import '../games/cora_dice/screens/cora_dice_screen.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: const Text('Jeux'),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _gameCard(
              context,
              'Ludo',
              'Jeu de plateau classique',
              Icons.grid_4x4,
              AppColors.neonBlue,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LudoTabScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _gameCard(
              context,
              'Cora Dice',
              'Jeu de dés camerounais • Virtual Coins',
              Icons.casino,
              AppColors.neonGreen,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CoraDiceScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
```

Puis dans `main.dart`, remplacez l'index 2 ou 3 par `const GamesScreen()`.

### 3️⃣ Tester l'application

```bash
flutter run
```

---

## 🧪 GUIDE DE TEST (10 minutes)

### Test 1 : Créer et rejoindre une partie

**Appareil/Émulateur 1 :**
1. Lancez l'app
2. Allez dans l'onglet **Cora** (ou Jeux → Cora Dice)
3. Appuyez sur **Créer**
4. Choisissez **2 joueurs**
5. Mode **Public**
6. Créez la partie
7. Notez le **code** (ex: A3F8D2)
8. Vous êtes dans le **lobby**

**Appareil/Émulateur 2 :**
1. Lancez l'app
2. Allez dans **Cora**
3. Vous devriez voir la partie dans la liste
4. Appuyez sur **Join**
5. Vous arrivez dans le lobby

**Dans les 2 appareils :**
1. Appuyez sur **PRÊT !**
2. La partie démarre automatiquement
3. Chacun lance les dés à son tour
4. Observez les animations

### Test 2 : Tester les règles

**Cas Cora (1+1) :**
- Lancez plusieurs fois jusqu'à obtenir 1+1
- ✅ Animation verte + explosion
- ✅ Message "CORA ! Double pot !"
- ✅ Victoire immédiate

**Cas 7 :**
- Lancez jusqu'à obtenir un total de 7 (ex: 3+4)
- ✅ Animation rouge + tremblement
- ✅ L'autre joueur gagne (vous avez perdu auto)

**Cas normal :**
- Joueur 1 : obtient 5+3 = 8
- Joueur 2 : obtient 2+2 = 4
- ✅ Joueur 1 gagne avec 8 points

### Test 3 : Chat dans le lobby

1. Dans le lobby, écrivez un message
2. Appuyez sur **Envoyer** (icône avion)
3. ✅ Le message apparaît en temps réel sur l'autre appareil

### Test 4 : Code privé

1. Créez une partie **Privée** avec 2 joueurs
2. Notez le code (ex: B7K3M9)
3. Sur l'autre appareil, appuyez sur **Rejoindre**
4. Entrez le code
5. ✅ Vous rejoignez la partie privée

### Test 5 : Parties multijoueurs (3-6 joueurs)

1. Créez une partie avec **4 joueurs**
2. Utilisez 3 appareils/émulateurs différents
3. Rejoignez tous la partie
4. Passez tous en **Prêt**
5. ✅ Tour par tour, chaque joueur lance
6. ✅ Le meilleur score gagne

---

## 🎨 PERSONNALISATION

### Changer les couleurs

Dans `lib/theme/app_theme.dart`, ajoutez :

```dart
// Couleurs Cora spécifiques
static const Color coraGreen = Color(0xFF00FF88);
static const Color coraOrange = Color(0xFFFF6B35);
```

Puis dans les écrans Cora, remplacez `AppColors.neonGreen` par `AppColors.coraGreen`.

### Ajouter des sons

1. Créez `assets/sounds/cora/`
2. Ajoutez :
   - `dice_roll.mp3`
   - `cora_win.mp3`
   - `seven_lose.mp3`
   - `win.mp3`

3. Dans `pubspec.yaml` :

```yaml
flutter:
  assets:
    - assets/sounds/cora/
```

4. Installez `audioplayers` :

```bash
flutter pub add audioplayers
```

5. Dans `game_screen.dart` :

```dart
import 'package:audioplayers/audioplayers.dart';

class _CoraGameScreenState extends State<CoraGameScreen> {
  final _audioPlayer = AudioPlayer();

  void _playSound(String name) async {
    await _audioPlayer.play(AssetSource('sounds/cora/$name.mp3'));
  }

  Future<void> _rollDice() async {
    // ... code existant
    _playSound('dice_roll');

    if (roll.isCora) {
      _playSound('cora_win');
    } else if (roll.isSeven) {
      _playSound('seven_lose');
    }
  }
}
```

### Ajouter des confettis sur victoire

1. Installez `confetti` :

```bash
flutter pub add confetti
```

2. Dans `game_screen.dart` :

```dart
import 'package:confetti/confetti.dart';

late ConfettiController _confettiController;

@override
void initState() {
  super.initState();
  _confettiController = ConfettiController(duration: const Duration(seconds: 3));
}

void _showResultDialog() {
  if (isWinner) {
    _confettiController.play();
  }
  // ... reste du code
}

// Dans build()
Stack(
  children: [
    // ... UI existante
    Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: _confettiController,
        blastDirectionality: BlastDirectionality.explosive,
        colors: const [
          AppColors.neonGreen,
          AppColors.neonYellow,
          AppColors.neonBlue,
        ],
      ),
    ),
  ],
)
```

---

## 🐛 DÉPANNAGE

### Erreur : "Table 'cora_rooms' doesn't exist"
→ **Solution** : Exécutez la migration SQL `05_cora_dice.sql` dans Supabase

### Erreur : "Function 'create_cora_room' doesn't exist"
→ **Solution** : Vérifiez que TOUTES les fonctions SQL ont été créées

### La partie ne démarre pas
→ **Solution** : Vérifiez que TOUS les joueurs ont appuyé sur "PRÊT !"

### Le realtime ne fonctionne pas
→ **Solution** : Dans Supabase Dashboard, vérifiez que la publication realtime est activée :
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE cora_games;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_rooms;
```

### Les animations sont saccadées
→ **Solution** : Utilisez un appareil physique ou un émulateur avec acceleration graphique

---

## 📊 STATISTIQUES DU PROJET

- **Fichiers créés** : 9
- **Lignes de code** : ~2500
- **Tables Supabase** : 4
- **Fonctions RPC** : 4
- **Écrans** : 4
- **Animations** : 3 types (dés, Cora, 7)

---

## 🎯 FONCTIONNALITÉS IMPLÉMENTÉES

✅ Création de parties (2-6 joueurs)
✅ Salles publiques et privées
✅ Code de 6 caractères pour rejoindre
✅ Lobby avec ready check
✅ Chat en temps réel
✅ Animations de dés (rotation)
✅ Effet spécial Cora (explosion verte)
✅ Effet spécial 7 (tremblement rouge)
✅ Calcul automatique des résultats
✅ Gestion des cas spéciaux (Cora, 7, égalité)
✅ Vibrations haptiques
✅ UI thème sombre professionnel
✅ Synchronisation temps réel (Supabase)
✅ Sécurité RLS

---

## 🚀 PROCHAINES ÉTAPES (Optionnelles)

### Niveau 1 : Polish
- [ ] Sons (dice_roll, cora_win, lose)
- [ ] Confettis sur victoire
- [ ] Améliorer les animations de dés (3D avec Rive)

### Niveau 2 : Features
- [ ] Historique des parties
- [ ] Statistiques joueur (% victoires, Cora count)
- [ ] Classement / Leaderboard
- [ ] Système de badges

### Niveau 3 : Avancé
- [ ] Mode tournoi
- [ ] Invitations push notifications
- [ ] Replays de parties
- [ ] Variantes de règles (Cora x3, x4, etc.)

---

## ✨ CONCLUSION

Vous avez maintenant un jeu **Cora Dice** complet et fonctionnel !

Le jeu est prêt pour :
- ✅ Jouer en local (debug)
- ✅ Déployer en production (après ajout gestion coins)
- ✅ Partager avec vos amis
- ✅ Être personnalisé (sons, animations, règles)

**Bon jeu ! 🎲🎉**

---

💡 **Astuce** : Pour tester rapidement, créez une partie publique à 2 joueurs, puis rejoignez-la depuis un autre appareil (ou émulateur). C'est le moyen le plus simple !
