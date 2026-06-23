// ============================================================
// BetTicketDetailScreen — Détails du pari (style 1xBet)
// ============================================================
// Affiche un ticket en plein écran avec :
//   - Header date + type + numéro de ticket
//   - Recap : nb événements + cote + mise + gain + statut
//   - Liste sélections détaillées :
//       sport . compétition / date
//       [crest] équipe A   vs   [crest] équipe B
//       market_label + cote
//       statut
//   - Boutons : DUPLIQUER LE COUPON (re-ajoute les selections au panier)
//
// Aucune action destructive : la duplication ajoute au panier sans
// rejouer le pari automatiquement (l'utilisateur valide explicitement).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart' show Sport, BettingMatch;
import '../state/bet_slip_controller.dart';
import '../widgets/bet_team_crest.dart';
import '../utils/bet_live_eval.dart';

class BetTicketDetailScreen extends StatelessWidget {
  /// Le ticket complet (résultat de la RPC get_my_bets_v2).
  final Map<String, dynamic> bet;
  /// Map match_id -> match live pour récupérer logos/scores en plus.
  final Map<String, BettingMatch> liveById;

  const BetTicketDetailScreen({
    super.key,
    required this.bet,
    this.liveById = const {},
  });

  @override
  Widget build(BuildContext context) {
    final status = bet['status']?.toString() ?? 'pending';
    final betType = bet['bet_type']?.toString() ?? 'simple';
    final stake = (bet['stake'] as num?)?.toInt() ?? 0;
    final totalOdds = (bet['total_odds'] as num?)?.toDouble() ?? 1;
    final payout = (bet['potential_payout'] as num?)?.toInt() ?? 0;
    final actualPayout = (bet['actual_payout'] as num?)?.toInt();
    final isVirtual = (bet['is_virtual'] as bool?) ?? false;
    final createdAt = DateTime.tryParse(bet['created_at']?.toString() ?? '');
    final betId = bet['id']?.toString() ?? '';
    final selections =
        (bet['selections'] as List?)?.cast<dynamic>() ?? const [];

    final settledCount = selections.where((s) {
      final st = (s as Map)['selection_status']?.toString() ?? 'pending';
      return st != 'pending';
    }).length;

    // ── Statut effectif du ticket (combine vs raw bd) ──
    // En combine : si AU MOINS 1 selection perdue -> ticket perdu (de facto)
    // meme si bet.status est encore 'pending' (settlement pas encore lance).
    // Idem : si toutes won -> ticket won.
    final anyLost = selections.any((s) =>
        (s as Map)['selection_status']?.toString() == 'lost');
    final allWon = selections.isNotEmpty && selections.every((s) =>
        (s as Map)['selection_status']?.toString() == 'won');
    final allDecided = selections.isNotEmpty && selections.every((s) {
      final st = (s as Map)['selection_status']?.toString() ?? 'pending';
      return st == 'won' || st == 'lost' || st == 'void';
    });
    String effectiveStatus = status;
    if (status == 'pending') {
      if (anyLost) {
        effectiveStatus = 'lost';
      } else if (allWon) {
        effectiveStatus = 'won';
      }
    }
    // ──────────────────────────────────────────────────────
    // CASHOUT (VENDRE) — Règles STRICTES style bookmaker pro
    // ──────────────────────────────────────────────────────
    // L'utilisateur ne doit PAS pouvoir vendre son ticket facilement.
    // C'est un mecanisme rare reserve aux situations bien specifiques.
    //
    // SIMPLE (1 selection) :
    //   - Match LIVE
    //   - Minute >= 70e (avant : pas d'urgence a vendre)
    //   - Pari actuellement WINNING ou LOCKED (TU MENES / ACQUIS)
    //   - Sinon : on attend la fin
    //
    // COMBINE (N selections) :
    //   - >= 50% des selections sont DEJA gagnees (acquis)
    //   - Au moins 1 selection encore pending (sinon le ticket se settle)
    //   - Aucune selection perdue (deja gere par anyLost)
    //
    // Dans tous les autres cas, le bouton est CACHE.
    // L'utilisateur subit le risque normal de son pari.
    // ──────────────────────────────────────────────────────
    bool canCashout = false;
    if (status == 'pending' && !anyLost && !allDecided) {
      if (selections.length == 1) {
        // SIMPLE : match live, minute >= 70, pari winning/locked
        final sel = selections.first as Map;
        final matchId = sel['match_id']?.toString() ?? '';
        final live = liveById[matchId];
        if (live != null && live.isLive && (live.minute ?? 0) >= 70) {
          final evalStatus = BetLiveEval.evaluate(
            marketCode: sel['market_code']?.toString() ?? '',
            match: live,
          );
          canCashout = evalStatus == BetLiveStatus.winning ||
              evalStatus == BetLiveStatus.locked;
        }
      } else {
        // COMBINE : >= 50% selections won + au moins 1 pending
        final wonCount = selections.where((s) =>
            (s as Map)['selection_status']?.toString() == 'won').length;
        final pendingCount = selections.where((s) =>
            (s as Map)['selection_status']?.toString() == 'pending').length;
        canCashout = wonCount * 2 >= selections.length && pendingCount > 0;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
                color: AppColors.neonRed.withValues(alpha: 0.7), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Détails du pari',
              style: TextStyle(
                color: AppColors.neonRed,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              )),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined,
                color: AppColors.textPrimary, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded,
                color: AppColors.textPrimary, size: 22),
            onPressed: () => _showActions(context, betId),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _header(createdAt, betType, betId, isVirtual),
            const SizedBox(height: 12),
            _recapCard(
              status: effectiveStatus,
              selectionsCount: selections.length,
              settledCount: settledCount,
              totalOdds: totalOdds,
              stake: stake,
              payout: payout,
              actualPayout: actualPayout,
            ),
            const SizedBox(height: 14),
            for (final sel in selections)
              _selectionCard(context, sel as Map),
            const SizedBox(height: 14),
            _actionButtons(context, effectiveStatus, payout, selections,
                canCashout: canCashout, stake: stake, totalOdds: totalOdds),
          ],
        ),
      ),
    );
  }

  Widget _header(DateTime? createdAt, String betType, String betId, bool isVirtual) {
    final date = createdAt != null
        ? _fmtDateLong(createdAt)
        : '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(date,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(
            betType == 'combine' ? 'Combiné' : 'Simple',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Text('Nº',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onLongPress: () => _copyToClipboard(betId),
              child: Text(_fullId(betId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
          ),
        ]),
        if (isVirtual) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _competitionBadge('Match Flash'),
          ),
        ],
      ]),
    );
  }

  Widget _recapCard({
    required String status,
    required int selectionsCount,
    required int settledCount,
    required double totalOdds,
    required int stake,
    required int payout,
    required int? actualPayout,
  }) {
    final (statusColor, statusLabel, statusIcon) = _statusVisuals(status);
    final showActual = status == 'won' || status == 'void' || status == 'refunded';
    final payoutColor = status == 'won'
        ? AppColors.neonGreen
        : (status == 'void' || status == 'refunded'
            ? AppColors.neonPurple
            : AppColors.textPrimary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        _recapRow('Nombre d\'événements :', '$selectionsCount',
            extra: '$settledCount de $selectionsCount terminés'),
        _divider(),
        _recapRow('Cote :', totalOdds.toStringAsFixed(2),
            valueColor: AppColors.textPrimary, valueBold: true),
        _divider(),
        _recapRow('Mise :', '$stake F',
            valueColor: AppColors.textPrimary, valueBold: true),
        _divider(),
        _recapRow(
          showActual ? 'Gain réel :' : 'Gains potentiels :',
          showActual
              ? '${actualPayout ?? payout} F'
              : '$payout F',
          valueColor: payoutColor, valueBold: true,
        ),
        _divider(),
        Row(children: [
          Text('Statut :',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              )),
        ]),
      ]),
    );
  }

  Widget _recapRow(String label, String value,
      {String? extra, Color? valueColor, bool valueBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
        const Spacer(),
        if (extra != null) ...[
          Text(extra,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
        ],
        Text(value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: valueBold ? FontWeight.w900 : FontWeight.w700)),
      ]),
    );
  }

  Widget _divider() => Container(
        height: 0.5,
        color: AppColors.divider.withValues(alpha: 0.4),
      );

  Widget _selectionCard(BuildContext context, Map sel) {
    final matchLabel = sel['match_label']?.toString() ?? '';
    final marketLabel = sel['market_label']?.toString() ?? '';
    final odds = (sel['odds'] as num?)?.toDouble() ?? 0;
    final selStatus = sel['selection_status']?.toString() ?? 'pending';
    final isVirtual = (sel['is_virtual'] as bool?) ?? false;
    final matchId = sel['match_id']?.toString() ?? '';
    final live = liveById[matchId];
    final (statusColor, statusLabel, statusIcon) = _statusVisuals(selStatus);
    final teams = _parseTeams(matchLabel);
    // Heuristique sport
    final isBasket = matchLabel.toLowerCase().contains('nba') ||
        matchLabel.toLowerCase().contains('basket');
    final sport = isBasket ? Sport.basketball : Sport.soccer;
    final competition = _detectCompetition(matchLabel, live);

    // ── Score final (priorise BD final_*_score, fallback sur live cache) ──
    final settled = selStatus == 'won' || selStatus == 'lost' || selStatus == 'void';
    int? finalHome = (sel['final_home_score'] as num?)?.toInt();
    int? finalAway = (sel['final_away_score'] as num?)?.toInt();
    // Fallback : si la BD n'a pas le score (ancien ticket pre-migration),
    // utilise le score live si le match est encore en cache memoire.
    if (settled && finalHome == null && live != null) {
      finalHome = live.homeScore;
      finalAway = live.awayScore;
    }
    final hasScore = finalHome != null && finalAway != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header competition + date ──
        Row(children: [
          Icon(
              isBasket
                  ? Icons.sports_basketball
                  : (isVirtual ? Icons.casino : Icons.sports_soccer),
              size: 13,
              color: AppColors.textMuted),
          const SizedBox(width: 5),
          Expanded(
            child: Text(competition,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
          ),
          if (isVirtual) _competitionBadge('FLASH'),
        ]),
        const SizedBox(height: 8),
        // ── Equipes + crests ──
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (teams.home.isNotEmpty)
            BetTeamCrest(
              name: teams.home,
              logoUrl: live?.homeLogo,
              sport: sport,
              size: 36,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(teams.home,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 4),
                // Centre : score final si dispo (settled match), sinon "vs"
                if (settled && hasScore)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                          width: 0.6),
                    ),
                    child: Text('$finalHome – $finalAway',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing: 0.3,
                        )),
                  )
                else
                  Text('vs',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(teams.away,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (teams.away.isNotEmpty)
            BetTeamCrest(
              name: teams.away,
              logoUrl: live?.awayLogo,
              sport: sport,
              size: 36,
            ),
        ]),
        const SizedBox(height: 10),
        // Score live si dispo
        if (live != null && live.isLive &&
            live.homeScore != null && live.awayScore != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.neonRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                    color: AppColors.neonRed, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                  "LIVE ${live.minute ?? 0}'  ${live.homeScore} - ${live.awayScore}",
                  style: TextStyle(
                    color: AppColors.neonRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        // ── Pari + cote ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Text(marketLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(odds.toStringAsFixed(3),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(height: 0.5, color: AppColors.divider.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Row(children: [
          Text('Statut :',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 5),
          Text(statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _competitionBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.neonBlue,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5)),
    );
  }

  Widget _actionButtons(BuildContext context, String status, int payout, List selections,
      {required bool canCashout, required int stake, required double totalOdds}) {
    // ── CASHOUT (Vendre) ── style 1xBet
    // Affiche UNIQUEMENT si :
    //   - Le ticket est encore vraiment jouable (canCashout = pas de selection lost,
    //     au moins 1 selection pending, ticket en pending DB).
    //
    // Formule cashout V1 (conservatrice, sans backend dedie) :
    //   prix = stake + max(0, (payout - stake) * facteur)
    //   facteur = (cote_decidee / cote_totale) * 0.45 - delta_temps
    //
    // Idee : on rembourse au moins la mise + une partie du gain potentiel
    // proportionnelle a ce qui est deja "acquis" (selections gagnees).
    // La maison garde une marge de securite (45% au lieu de 100%) pour
    // compenser le risque restant sur les selections en cours.
    int? cashoutPrice;
    if (canCashout) {
      // Cote deja acquise = produit des cotes des selections WON
      // (les selections void comptent comme cote 1.0 = neutre)
      double acquiredOdds = 1;
      bool anyWon = false;
      for (final s in selections) {
        final m = s as Map;
        final st = m['selection_status']?.toString() ?? 'pending';
        final o = (m['odds'] as num?)?.toDouble() ?? 1;
        if (st == 'won') {
          acquiredOdds *= o;
          anyWon = true;
        }
      }
      if (totalOdds <= 1 || !anyWon) {
        // Aucune selection gagnee -> cashout = retour de mise reduit (-20%)
        cashoutPrice = (stake * 0.80).round();
      } else {
        // Proportion de cote acquise sur cote totale
        final progress = (acquiredOdds / totalOdds).clamp(0.0, 1.0);
        // Prix = stake + gain potentiel * progress * facteur securite (0.45)
        final bonus = (payout - stake) * progress * 0.45;
        cashoutPrice = (stake + bonus).round();
        // Cap : jamais plus que payout (sinon perte garantie maison)
        if (cashoutPrice > payout * 0.9) cashoutPrice = (payout * 0.9).round();
        // Min : au moins 80% de la mise
        if (cashoutPrice < (stake * 0.8).round()) {
          cashoutPrice = (stake * 0.80).round();
        }
      }
    }

    return Column(children: [
      // Banniere d'etat informative pour les tickets perdus/decides
      if (status == 'lost') ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.neonRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.neonRed.withValues(alpha: 0.4), width: 0.6),
          ),
          child: Row(children: [
            Icon(Icons.cancel_rounded,
                size: 16, color: AppColors.neonRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Ticket perdu — au moins une sélection a été perdue. '
                  'Le combiné ne peut plus être vendu.',
                  style: TextStyle(
                    color: AppColors.neonRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (canCashout && cashoutPrice != null) ...[
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => _showCashoutDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text('VENDRE POUR $cashoutPrice F',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height: 10),
      ],
      SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          icon: Icon(Icons.content_copy_rounded,
              size: 16, color: AppColors.neonBlue),
          label: Text('DUPLIQUER LE COUPON DE PARI',
              style: TextStyle(
                color: AppColors.neonBlue,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5)),
          onPressed: () => _duplicateCoupon(context, selections),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.neonBlue, width: 1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]);
  }

  void _showCashoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Cashout',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900)),
        content: Text(
            'La vente anticipée du ticket sera disponible prochainement.',
            style: TextStyle(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: TextStyle(color: AppColors.neonBlue)),
          ),
        ],
      ),
    );
  }

  void _duplicateCoupon(BuildContext context, List selections) {
    final ctrl = BetSlipController.instance;
    int added = 0;
    int skipped = 0;
    for (final raw in selections) {
      final s = raw as Map;
      final matchId = s['match_id']?.toString() ?? '';
      if (matchId.isEmpty) continue;
      if (ctrl.hasMatch(matchId)) {
        skipped++;
        continue;
      }
      final odds = (s['odds'] as num?)?.toDouble() ?? 1.01;
      final sel = BetSelection(
        matchId: matchId,
        matchLabel: s['match_label']?.toString() ?? '',
        marketCode: s['market_code']?.toString() ?? '',
        marketLabel: s['market_label']?.toString() ?? '',
        odds: odds,
        kickoff: DateTime.now().add(const Duration(hours: 1)),
        isLive: (s['is_live'] as bool?) ?? false,
        isVirtual: (s['is_virtual'] as bool?) ?? false,
      );
      ctrl.toggle(sel);
      added++;
    }
    final msg = skipped > 0
        ? '$added ajoutée(s), $skipped ignorée(s) (déjà au panier)'
        : '$added sélection${added > 1 ? 's' : ''} ajoutée${added > 1 ? 's' : ''} au panier';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.neonGreen,
      duration: const Duration(seconds: 2),
      content: Text(msg,
          style: const TextStyle(
            color: Colors.black, fontWeight: FontWeight.w900)),
    ));
    Navigator.pop(context);
  }

  void _showActions(BuildContext context, String betId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.copy_all_rounded, color: AppColors.textPrimary),
            title: Text('Copier le numéro',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800)),
            onTap: () {
              Navigator.pop(ctx);
              _copyToClipboard(betId);
            },
          ),
          ListTile(
            leading: Icon(Icons.share_rounded, color: AppColors.textPrimary),
            title: Text('Partager',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800)),
            onTap: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
  }

  void _copyToClipboard(String betId) {
    Clipboard.setData(ClipboardData(text: _fullId(betId)));
  }

  (Color, String, IconData) _statusVisuals(String status) {
    switch (status) {
      case 'won':
        return (AppColors.neonGreen, 'Gagné', Icons.check_circle_rounded);
      case 'lost':
        return (AppColors.neonRed, 'Perdu', Icons.cancel_rounded);
      case 'void':
      case 'refunded':
        return (AppColors.neonPurple, 'Remboursé', Icons.do_not_disturb_rounded);
      case 'cashed_out':
        return (AppColors.neonBlue, 'Encaissé', Icons.payments_rounded);
      case 'pending':
      default:
        return (AppColors.neonBlue, 'Accepté', Icons.check_circle_rounded);
    }
  }

  ({String home, String away}) _parseTeams(String label) {
    final patterns = [
      RegExp(r'\s+vs\.?\s+', caseSensitive: false),
      RegExp(r'\s+-\s+'),
    ];
    for (final p in patterns) {
      final parts = label.split(p);
      if (parts.length == 2) {
        return (home: parts[0].trim(), away: parts[1].trim());
      }
    }
    return (home: label, away: '');
  }

  String _detectCompetition(String matchLabel, BettingMatch? live) {
    if (live != null && live.league.isNotEmpty) {
      final prefix = matchLabel.toLowerCase().contains('basket') ||
              matchLabel.toLowerCase().contains('nba')
          ? 'Basket'
          : 'Football';
      return '$prefix . ${live.league}';
    }
    if (matchLabel.toLowerCase().contains('nba') ||
        matchLabel.toLowerCase().contains('basket')) {
      return 'Basket';
    }
    return 'Football';
  }

  String _fullId(String id) {
    if (id.isEmpty) return '——';
    return id.replaceAll('-', '').toUpperCase();
  }

  String _fmtDateLong(DateTime dt) {
    final l = dt.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final yy = l.year.toString();
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yy ($hh:$mn)';
  }
}
