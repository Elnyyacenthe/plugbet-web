// ============================================================
// Plugbet – Catalogue de jeux PARTAGE
// ============================================================
// Source unique de verite pour la liste des mini-jeux : consommee a la
// fois par l'ecran Jeux (games_screen) et par les sections Top / Jeux /
// Casino de l'ecran Populaire (betting_screen). Chaque entree porte son
// builder de navigation + ses categories (filtres) + regles optionnelles.
// ============================================================

import 'package:flutter/material.dart';

import '../widgets/game_rules_dialog.dart';
import '../fantasy/screens/fantasy_home_screen.dart';
import '../ludo_v2/screens/ludo_menu_screen.dart';
import 'cora_dice/screens/cora_dice_screen.dart';
import 'checkers/screens/checkers_screen.dart';
import 'solitaire/screens/solitaire_screen.dart';
import 'aviator/screens/aviator_screen.dart';
import 'blackjack/screens/blackjack_screen.dart';
import 'roulette/screens/roulette_screen.dart';
import 'coinflip/screens/coinflip_screen.dart';
import 'slots_777/screens/slots_screen.dart';
import 'wheel/screens/wheel_screen.dart';
import 'apple_fortune/screens/apple_fortune_screen.dart';
import 'mines/screens/mines_screen.dart';
import 'penalty/screens/penalty_bet_screen.dart';

enum GameCategory { classic, casino, multiplayer, arcade, fantasy }

class GameEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String imageAsset;
  final String onlineCount;
  final Set<GameCategory> tags;
  final bool hot;
  final WidgetBuilder builder;
  final GameRules? rules;

  const GameEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageAsset,
    required this.onlineCount,
    required this.tags,
    required this.builder,
    this.hot = false,
    this.rules,
  });

  bool matches(String query, GameCategory? tag) {
    final byTag = tag == null || tags.contains(tag);
    if (!byTag) return false;
    if (query.isEmpty) return true;
    final text = '$title $subtitle'.toLowerCase();
    return text.contains(query.toLowerCase());
  }
}

/// Catalogue complet (non-const car les builders sont des closures).
final List<GameEntry> kGamesCatalog = [
  GameEntry(
    title: 'Fantasy',
    subtitle: 'Premier League Fantasy',
    icon: Icons.sports_soccer_rounded,
    imageAsset: 'assets/games/fantasy.png',
    onlineCount: '2.9k',
    tags: const {GameCategory.fantasy},
    hot: true,
    builder: (_) => const FantasyHomeScreen(),
  ),
  GameEntry(
    title: 'Ludo',
    subtitle: 'Plateau classique 2-4 joueurs',
    icon: Icons.dashboard_rounded,
    imageAsset: 'assets/games/ludo.jpg',
    onlineCount: '2.4k',
    tags: const {GameCategory.classic, GameCategory.multiplayer},
    hot: true,
    builder: (_) => const LudoV2MenuScreen(),
    rules: GameRulesLibrary.ludo,
  ),
  GameEntry(
    title: 'Cora Dice',
    subtitle: 'Jeu de dés multijoueur',
    icon: Icons.casino_rounded,
    imageAsset: 'assets/games/cora_dice.jpg',
    onlineCount: '1.8k',
    tags: const {GameCategory.casino, GameCategory.multiplayer},
    hot: true,
    builder: (_) => const CoraDiceScreen(),
    rules: GameRulesLibrary.coraDice,
  ),
  GameEntry(
    title: 'Dames',
    subtitle: 'Plateau 8x8 1v1',
    icon: Icons.grid_4x4_rounded,
    imageAsset: 'assets/games/dames.jpg',
    onlineCount: '1.2k',
    tags: const {GameCategory.classic, GameCategory.multiplayer},
    builder: (_) => const CheckersScreen(),
    rules: GameRulesLibrary.checkers,
  ),
  GameEntry(
    title: 'Aviator',
    subtitle: 'Crash multiplier',
    icon: Icons.flight_takeoff_rounded,
    imageAsset: 'assets/games/aviator.jpg',
    onlineCount: '3.7k',
    tags: const {GameCategory.casino, GameCategory.arcade},
    hot: true,
    builder: (_) => const AviatorScreen(),
    rules: GameRulesLibrary.aviator,
  ),
  GameEntry(
    title: 'Blackjack',
    subtitle: 'Joueurs vs dealer',
    icon: Icons.style_rounded,
    imageAsset: 'assets/games/blackjack.jpg',
    onlineCount: '1.5k',
    tags: const {GameCategory.casino, GameCategory.multiplayer},
    builder: (_) => const BlackjackScreen(),
    rules: GameRulesLibrary.blackjack,
  ),
  GameEntry(
    title: 'Roulette',
    subtitle: 'Rouge noir et numéros',
    icon: Icons.donut_large_rounded,
    imageAsset: 'assets/games/roulette.jpg',
    onlineCount: '1.1k',
    tags: const {GameCategory.casino, GameCategory.multiplayer},
    builder: (_) => const RouletteScreen(),
    rules: GameRulesLibrary.roulette,
  ),
  GameEntry(
    title: 'Apple Fortune',
    subtitle: 'Pyramide multiplicateurs',
    icon: Icons.change_history_rounded,
    imageAsset: 'assets/games/apple_fortune.png',
    onlineCount: '936',
    tags: const {GameCategory.arcade},
    builder: (_) => const AppleFortuneScreen(),
    rules: GameRulesLibrary.appleFortune,
  ),
  GameEntry(
    title: 'Mines',
    subtitle: 'Diamants vs bombes',
    icon: Icons.diamond_rounded,
    imageAsset: 'assets/games/mines.jpg',
    onlineCount: '884',
    tags: const {GameCategory.casino, GameCategory.arcade},
    builder: (_) => const MinesScreen(),
    rules: GameRulesLibrary.mines,
  ),
  GameEntry(
    title: 'Pile ou Face',
    subtitle: 'Duel 1v1',
    icon: Icons.monetization_on_rounded,
    imageAsset: 'assets/games/coinflip.jpg',
    onlineCount: '742',
    tags: const {GameCategory.classic, GameCategory.multiplayer},
    builder: (_) => const CoinflipScreen(),
    rules: GameRulesLibrary.coinflip,
  ),
  GameEntry(
    title: 'Solitaire',
    subtitle: 'Klondike solo',
    icon: Icons.layers_rounded,
    imageAsset: 'assets/games/solitaire.png',
    onlineCount: '693',
    tags: const {GameCategory.classic},
    builder: (_) => const SolitaireScreen(),
    rules: GameRulesLibrary.solitaire,
  ),
  GameEntry(
    title: 'Penalty',
    subtitle: '5 tirs mise libre',
    icon: Icons.sports_soccer_rounded,
    imageAsset: 'assets/games/penalty_shooters_2.jpg',
    onlineCount: '524',
    tags: const {GameCategory.arcade},
    builder: (_) => const PenaltyBetScreen(),
  ),
  GameEntry(
    title: 'Big Win 777',
    subtitle: 'Machine à sous',
    icon: Icons.casino_outlined,
    imageAsset: 'assets/games/big_win_777.png',
    onlineCount: '2.1k',
    tags: const {GameCategory.casino, GameCategory.arcade},
    hot: true,
    builder: (_) => const SlotsScreen(),
  ),
  GameEntry(
    title: 'Plugbet Wheel',
    subtitle: 'Roue de la fortune',
    icon: Icons.brightness_low,
    imageAsset: 'assets/games/wheel.jpg',
    onlineCount: '817',
    tags: const {GameCategory.casino, GameCategory.arcade},
    builder: (_) => const WheelScreen(),
  ),
];

/// Sous-ensemble casino (utilise par la section Casino).
List<GameEntry> get kCasinoGames =>
    kGamesCatalog.where((g) => g.tags.contains(GameCategory.casino)).toList();
