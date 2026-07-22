// ============================================================
// Plugbet – Provider des promotions
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/promo_item.dart';

class PromoProvider extends ChangeNotifier {
  List<PromoItem> _promotions = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<PromoItem> get promotions => _promotions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Récupérer les promotions actives (exclut le grand prix si on veut les lister à part)
  List<PromoItem> get activePromotions =>
      _promotions.where((p) => p.isActive).toList();

  /// Retrouve une promo par son identifiant (pour PromoDetailScreen).
  PromoItem? byId(String id) {
    for (final p in _promotions) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Récupérer spécifiquement la promotion de type Grand Prix
  PromoItem? get grandPrixPromo {
    try {
      return _promotions.firstWhere((p) => p.isGrandPrix && p.isActive);
    } catch (_) {
      return null;
    }
  }

  /// Charger les promotions (simulation d'appel réseau avec délai de 1.5 seconde)
  Future<void> loadPromotions({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Simulation du délai réseau pour afficher le shimmer
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      // Données mockées haut de gamme
      _promotions = [
        // ── Fonctionnalité 2Up (paiement anticipé) ──
        PromoItem(
          id: 'promo_2up',
          title: '2UP — DEUX BUTS D\'AVANCE, TU GAGNES DÉJÀ !',
          description:
              'Ton équipe mène de 2 buts ? Ton pari est payé immédiatement, même si le score change ensuite.',
          imageUrl:
              'assets/images/2up.png', // pas d'affiche : header pictogramme (flèche montante)
          winnersCount: 0,
          badgeLabel: 'Plugbet 2UP',
          actionLabel: 'EN SAVOIR PLUS',
          highlightedReward: 'PAIEMENT ANTICIPÉ',
          longDescription:
              'Le 2Up récompense l\'avance de ton équipe sans jamais réduire ta cote. '
              'Si l\'équipe ou le joueur sur lequel tu as parié atteint le seuil d\'avance '
              'requis en cours de match, ton pari est immédiatement réglé GAGNANT — '
              'même si l\'adversaire revient au score ou l\'emporte à la fin.\n\n'
              'Et si ton équipe gagne sans jamais atteindre ce seuil ? Ton pari reste '
              'gagnant normalement à la fin du match. Le 2Up est un bonus de déclenchement '
              'anticipé, jamais une condition supplémentaire.',
          conditions: [
            'Paris pré-match, marché « Résultat final » (1X2), sélection 1 ou 2 uniquement.',
            'Le match nul (N) n\'est jamais éligible au 2Up.',
            'Seuils : football 2 buts · basket 20 pts · tennis 2 sets · foot US 17 pts · baseball 5 runs.',
            'La cote n\'est jamais réduite pour ce paiement anticipé.',
            'Non applicable aux Bet Builders ni aux autres marchés.',
            'En combiné, la sélection 2Up est gagnante mais les autres doivent gagner normalement.',
          ],
        ),
        PromoItem(
          id: 'promo_new_season',
          title: 'LES GRANDS CHAMPIONNATS SONT DE RETOUR !',
          description:
              'La Premier League, La Liga, la Serie A et la Bundesliga reprennent. Prépare tes paris et vis une nouvelle saison pleine d’émotions.',
          imageUrl: 'assets/images/new_season_2026.png',
          winnersCount: 0,
          badgeLabel: 'SAISON 2026/27',
          actionLabel: 'PARIER MAINTENANT',
          highlightedReward: 'NOUVELLE SAISON',
          longDescription:
              'Le coup d’envoi de la saison 2026/2027 est enfin là ! Les plus grands '
              'championnats européens reviennent avec des affiches prestigieuses, des '
              'derbys explosifs et des milliers d’opportunités de paris sur Plugbet.\n\n'
              'Retrouve chaque semaine les meilleures cotes sur la Premier League, '
              'La Liga, la Serie A et la Bundesliga. Que tu sois passionné de football '
              'ou amateur de paris sportifs, prépare-toi à vibrer dès les premiers matchs '
              'de la saison et profite de toute l’action en direct.',
          conditions: [
            'Paris disponibles avant et pendant les matchs.',
            'Cotes mises à jour en temps réel.',
            'Des centaines de marchés disponibles sur chaque rencontre.',
            'Fonctionnalités exclusives Plugbet comme le 2UP sur les matchs éligibles.',
            'Les offres promotionnelles peuvent varier selon les compétitions.',
            'Réservé aux utilisateurs majeurs conformément à la réglementation en vigueur.',
          ],
        ),
        PromoItem(
          id: 'promo_plugshield',
          title: 'PLUGSHIELD — UN COMBINÉ, UNE SECONDE CHANCE !',
          description:
              'Rate une seule sélection sur un combiné éligible et PlugShield protège ton pari.',
          imageUrl: 'assets/images/plugshield.png',
          winnersCount: 0,
          badgeLabel: 'PLUGSHIELD',
          actionLabel: 'EN SAVOIR PLUS',
          highlightedReward: 'COMBINÉ PROTÉGÉ',
          longDescription:
              'PlugShield protège tes paris combinés contre une seule mauvaise sélection. '
              'Si une unique sélection échoue sur un combiné éligible, ton pari peut être '
              'remboursé selon les conditions de l\'offre.\n\n'
              'Tu continues à viser de grosses cotes sans craindre qu\'un seul résultat '
              'ne fasse tout perdre. PlugShield te donne une véritable seconde chance.',
          conditions: [
            'Valable uniquement sur les paris combinés.',
            'Minimum 5 sélections.',
            'Une seule sélection perdante est autorisée.',
            'Le remboursement est effectué en bonus de pari.',
            'Montant maximum remboursé selon la promotion en cours.',
            'Non cumulable avec certaines offres promotionnelles.',
          ],
        ),
        PromoItem(
          id: 'promo_plugsafe',
          title: 'PLUGSAFE — TON PREMIER PARI EST PROTÉGÉ !',
          description:
              'Découvre Plugbet en toute confiance : si ton premier pari éligible perd, ta mise est remboursée en bonus.',
          imageUrl: 'assets/images/plugsafe.png',
          winnersCount: 0,
          badgeLabel: 'PLUGSAFE',
          actionLabel: 'EN SAVOIR PLUS',
          highlightedReward: 'MISE REMBOURSÉE',
          longDescription:
              'PlugSafe accompagne les nouveaux joueurs dès leur premier pari. '
              'Si ton premier pari éligible est perdant, Plugbet te rembourse automatiquement '
              'ta mise sous forme de bonus afin que tu puisses tenter à nouveau ta chance.\n\n'
              'Une façon simple de découvrir toutes les émotions du pari sportif avec '
              'plus de sérénité.',
          conditions: [
            'Réservé aux nouveaux utilisateurs.',
            'Valable uniquement sur le premier pari sportif.',
            'Montant maximum remboursé défini par la promotion.',
            'Le remboursement est crédité sous forme de bonus.',
            'Une seule utilisation par compte.',
            'Offre soumise aux conditions générales de Plugbet.',
          ],
        ),
        PromoItem(
          id: 'promo_pluglock',
          title: 'PLUGLOCK — TA COTE, TON CONTRÔLE !',
          description:
              'Verrouille temporairement une cote avant qu\'elle ne change et valide ton pari en toute tranquillité.',
          imageUrl: 'assets/images/pluglock.png',
          winnersCount: 0,
          badgeLabel: 'PLUGLOCK',
          actionLabel: 'EN SAVOIR PLUS',
          highlightedReward: 'COTE VERROUILLÉE',
          longDescription:
              'Les cotes évoluent constamment, surtout pendant les matchs en direct. '
              'Grâce à PlugLock, tu peux verrouiller temporairement une cote afin de '
              'finaliser ton ticket sans subir une variation immédiate.\n\n'
              'Profite du bon moment pour préparer ton pari et joue avec davantage de contrôle.',
          conditions: [
            'Disponible uniquement sur certains événements.',
            'Verrouillage valable pendant une durée limitée.',
            'Une fois expirée, la cote redevient dynamique.',
            'Disponible selon les marchés proposés.',
            'Peut être suspendu lors d\'événements majeurs en direct.',
            'Sous réserve de disponibilité technique.',
          ],
        ),
        PromoItem(
          id: 'promo_plugboost',
          title: 'PLUGBOOST — TES GAINS PRENNENT DE LA HAUTEUR !',
          description:
              'Profite d\'un bonus automatique sur tes gains lorsque ton pari remplit les conditions de l\'offre.',
          imageUrl: 'assets/images/plugboost.png',
          winnersCount: 0,
          badgeLabel: 'PLUGBOOST',
          actionLabel: 'EN SAVOIR PLUS',
          highlightedReward: 'JUSQU’À +25%',
          longDescription:
              'PlugBoost récompense les joueurs avec un bonus automatique sur leurs gains. '
              'Selon le type de pari et les conditions de la promotion, un pourcentage '
              'supplémentaire est ajouté à tes gains sans aucune démarche.\n\n'
              'Plus tu réussis tes paris éligibles, plus tes récompenses augmentent.',
          conditions: [
            'Disponible sur certains paris éligibles.',
            'Le bonus varie selon les promotions en cours.',
            'Le pourcentage maximum est communiqué avant validation.',
            'Le bonus est automatiquement ajouté aux gains.',
            'Offre non cumulable avec certaines promotions.',
            'Conditions générales applicables.',
          ],
        ),
      ];
      _errorMessage = null;
    } catch (e) {
      _errorMessage =
          "Impossible de charger les promotions. Veuillez réessayer.";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Permet de simuler un état vide pour les tests
  void simulateEmptyState() {
    _promotions = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
