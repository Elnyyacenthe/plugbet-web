// ============================================================
// GameRulesDialog — Modal reutilisable "Comment jouer ?"
// Affiche les regles et le gameplay d'un jeu
// ============================================================
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Regles d'un jeu.
class GameRules {
  final String title;
  final String emoji;
  final String description;
  final List<String> howToPlay;
  final List<String>? tips;

  const GameRules({
    required this.title,
    required this.emoji,
    required this.description,
    required this.howToPlay,
    this.tips,
  });
}

/// Affiche un modal avec les regles d'un jeu.
/// Usage :
/// ```dart
/// GameRulesDialog.show(context, GameRulesLibrary.appleFortune);
/// ```
class GameRulesDialog extends StatelessWidget {
  final GameRules rules;

  const GameRulesDialog({super.key, required this.rules});

  static Future<void> show(BuildContext context, GameRules rules) {
    return showDialog(
      context: context,
      builder: (_) => GameRulesDialog(rules: rules),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.neonGreen.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  Text(rules.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rules.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Contenu scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    Text(
                      rules.description,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Comment jouer
                    _sectionHeader('🎯  ${t.gameHowToPlay}'),
                    const SizedBox(height: 10),
                    ...rules.howToPlay.asMap().entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.neonGreen
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: TextStyle(
                                    color: AppColors.neonGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.value,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Tips (optionnels)
                    if (rules.tips != null && rules.tips!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionHeader('💡  ${t.gameTips}'),
                      const SizedBox(height: 8),
                      ...rules.tips!.map((tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '•  ',
                                  style: TextStyle(
                                    color: AppColors.neonYellow,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    tip,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),

            // Bouton fermer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    t.gameUnderstood,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.neonGreen,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ============================================================
// Bibliotheque des regles pour chaque jeu
// ============================================================
class GameRulesLibrary {
  static const appleFortune = GameRules(
    title: 'Apple of Fortune',
    emoji: '🍎',
    description:
        "Grimpez la pyramide en choisissant une pomme par ligne. "
        "Chaque bonne pomme fait grimper votre multiplicateur. "
        "Une mauvaise et vous perdez tout !",
    howToPlay: [
      'Choisissez votre mise et lancez la partie.',
      'Sur chaque ligne, tapez une case pour reveler une pomme.',
      'Si la pomme est bonne : vous montez d\'une ligne et le multiplicateur augmente.',
      'Si la pomme est pourrie : vous perdez votre mise.',
      'Vous pouvez CASH OUT a tout moment pour encaisser le gain actuel.',
    ],
    tips: [
      'Plus vous montez, plus le gain est eleve mais le risque augmente.',
      'Le multiplicateur part de x1.9 et double presque a chaque ligne.',
      'Ne soyez pas avide : un cash out a x7 vaut mieux que zero a x30.',
    ],
  );

  static const aviator = GameRules(
    title: 'Aviator',
    emoji: '✈️',
    description:
        "L'avion decolle et un multiplicateur grimpe a toute vitesse. "
        "Cashouté avant qu'il ne s'ecrase pour empocher votre gain !",
    howToPlay: [
      'Pendant le countdown, placez votre mise (min 90 FCFA).',
      'L\'avion decolle et le multiplicateur commence a monter.',
      'Tapez CASHOUT a tout moment pour empocher mise × multiplicateur.',
      'Si vous ne cashoutez pas avant le crash, vous perdez la mise.',
      'Vous pouvez placer jusqu\'a 2 mises simultanement.',
    ],
    tips: [
      'Utilisez l\'auto cash-out pour garantir un gain minimum sans stress.',
      'Les crashs arrivent souvent sous x2, soyez patient.',
      'Jouez avec des petites mises regulieres plutot qu\'une grosse.',
    ],
  );

  static const ludo = GameRules(
    title: 'Ludo',
    emoji: '🎲',
    description:
        "Jeu de plateau classique : soyez le premier a ramener "
        "vos 4 pions a la maison en lancant le de.",
    howToPlay: [
      'Lancez le de a votre tour.',
      'Faites 6 pour sortir un pion de la base.',
      'Avancez vos pions le long du circuit.',
      'Capturez les pions adverses en tombant dessus.',
      'Le premier joueur a rentrer ses 4 pions gagne.',
    ],
    tips: [
      'Priorisez la capture de pions adverses.',
      'Gardez vos pions groupes quand possible.',
    ],
  );

  static const coraDice = GameRules(
    title: 'Cora Dice',
    emoji: '🎲',
    description:
        "Jeu de des camerounais. Chaque joueur lance 2 des. "
        "Le total le plus eleve gagne !",
    howToPlay: [
      'Rejoignez une salle avec une mise.',
      'A votre tour, tapez pour lancer les 2 des.',
      'Le joueur avec le total le plus eleve remporte le pot.',
      'Attention : 7 (1+6, 2+5, 3+4) fait perdre !',
      'CORA (double 1) fait gagner double !',
    ],
    tips: [
      'Les jetees extremes (2 ou 12) sont rares mais gagnantes.',
    ],
  );

  static const checkers = GameRules(
    title: 'Dames',
    emoji: '♟️',
    description:
        "Jeu de dames classique sur plateau 8×8. Capturez tous "
        "les pions adverses pour gagner.",
    howToPlay: [
      'Deplacez vos pions en diagonale.',
      'Sauter un pion adverse pour le capturer (obligatoire).',
      'Enchainez les captures multiples si possible.',
      'Atteindre la derniere rangee promeut votre pion en roi.',
      'Le roi peut se deplacer dans toutes les directions.',
    ],
  );

  static const roulette = GameRules(
    title: 'Roulette',
    emoji: '🎡',
    description:
        "Pariez sur rouge, noir, pair, impair ou un numero specifique. "
        "Une fois les mises placees, la roue tourne !",
    howToPlay: [
      'Choisissez votre type de pari et le montant.',
      'Rouge/Noir/Pair/Impair : gain x2.',
      'Numero exact : gain x36.',
      'Zero (0) vert : la maison gagne tout (sauf si pari sur 0).',
      'La roue tourne automatiquement apres les mises.',
    ],
  );

  static const blackjack = GameRules(
    title: 'Blackjack',
    emoji: '🃏',
    description:
        "Battez le dealer sans depasser 21. Obtenez un blackjack "
        "(21 avec 2 cartes) pour un bonus x2.5 !",
    howToPlay: [
      'Placez votre mise.',
      'Vous recevez 2 cartes, le dealer aussi.',
      'HIT pour tirer une carte supplementaire.',
      'STAND pour arreter et laisser le dealer jouer.',
      'Le dealer tire jusqu\'a 17. Celui qui approche 21 sans depasser gagne.',
    ],
    tips: [
      'Tirez systematiquement si votre main ≤ 11.',
      'Tenez si ≥ 17.',
      'Entre 12 et 16, depend de la carte visible du dealer.',
    ],
  );

  static const coinflip = GameRules(
    title: 'Pile ou Face',
    emoji: '🪙',
    description:
        "Duel 1v1 le plus simple : choisissez pile ou face, "
        "le gagnant empoche toute la mise.",
    howToPlay: [
      'Creez une salle avec un montant de mise.',
      'Un adversaire rejoint avec le code.',
      'Chaque joueur choisit pile ou face.',
      'La piece est lancee cote serveur.',
      'Le gagnant empoche les 2 mises.',
    ],
  );

  static const mines = GameRules(
    title: 'Mines',
    emoji: '💣',
    description:
        "Grille de 25 cases cachees. Certaines contiennent des mines 💣, "
        "les autres des diamants 💎. Revelez les cases une par une, "
        "et cashoutez avant de tomber sur une mine !",
    howToPlay: [
      'Choisissez votre mise et le nombre de mines (3 a 20).',
      'Cliquez COMMENCER pour lancer la partie.',
      'Tapez sur une case pour la reveler.',
      'Si c\'est un diamant : le multiplicateur augmente.',
      'Si c\'est une mine : vous perdez toute la mise.',
      'Tapez CASH OUT a tout moment pour encaisser vos gains.',
    ],
    tips: [
      'Plus il y a de mines, plus les multiplicateurs augmentent vite.',
      'Commencez avec 3-5 mines pour apprendre.',
      'Ne soyez pas avide : cash out au bon moment, c\'est tout l\'art du jeu.',
    ],
  );

  static const solitaire = GameRules(
    title: 'Solitaire',
    emoji: '♠️',
    description:
        "Solitaire Klondike classique. Rangez toutes les cartes "
        "dans les 4 fondations par couleur (A → K).",
    howToPlay: [
      'Empilez les cartes en decroissant et en alternant couleurs.',
      'Deplacez les sequences vers d\'autres colonnes.',
      'Montez chaque carte vers sa fondation (A, 2, 3... K).',
      'Piochez du stock quand vous etes bloque.',
      'Gagnez en completant les 4 fondations.',
    ],
  );
}
