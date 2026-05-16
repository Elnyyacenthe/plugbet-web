// ============================================================
// ROULETTE - Ecran de jeu redesigne (style casino)
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
import '../models/roulette_models.dart';
import '../services/roulette_service.dart';
import '../../../widgets/network_lost_overlay.dart';

class RLTGameScreen extends StatefulWidget {
  final String gameId;
  const RLTGameScreen({super.key, required this.gameId});
  @override
  State<RLTGameScreen> createState() => _RLTGameScreenState();
}

class _RLTGameScreenState extends State<RLTGameScreen>
    with SingleTickerProviderStateMixin {
  final _svc = RouletteService.instance;
  RouletteGame? _game;
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _pollTimer; // fallback si realtime meurt
  bool _placing = false;
  bool _spinning = false;

  /// Mise courante (chip selectionne). Un click sur un numero/zone applique
  /// directement cette mise (pas de bouton "miser" intermediaire).
  int _currentChip = 50;

  late AnimationController _wheelCtrl;
  double _wheelAngle = 0;

  String get _myId => _svc.currentUserId ?? '';

  static const _redNumbers = {
    1, 3, 5, 7, 9, 12, 14, 16, 18,
    19, 21, 23, 25, 27, 30, 32, 34, 36
  };

  static const _chips = [50, 100, 250, 500, 1000];

  @override
  void initState() {
    super.initState();
    _wheelCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
      try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
    });
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    _pollTimer?.cancel();
    if (_channel != null) _svc.unsubscribe(_channel!);
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    _game = await _svc.getGame(widget.gameId);
    _channel = _svc.subscribeGame(
      widget.gameId,
      _onUpdate,
      onConnectionLost: _startPollingFallback,
    );
    if (mounted) setState(() => _loading = false);
  }

  /// Polling toutes les 2s si le realtime meurt. Auto-stop a la fin.
  void _startPollingFallback() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || (_game?.gameState.isFinished ?? false)) {
        t.cancel();
        _pollTimer = null;
        return;
      }
      final fresh = await _svc.getGame(widget.gameId);
      if (fresh != null) _onUpdate(fresh);
    });
  }

  void _onUpdate(RouletteGame g) {
    if (!mounted) return;
    final wasBetting = _game?.gameState.phase == 'betting';
    setState(() => _game = g);

    if (wasBetting && g.gameState.phase == 'spinning') {
      _animateSpin(g.gameState.result ?? 0);
    }
    if (g.gameState.isFinished) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _showResult();
      });
    }
  }

  void _animateSpin(int result) {
    final targetAngle = (result / 37) * 2 * pi + 6 * 2 * pi;
    _wheelCtrl.reset();
    _wheelCtrl.forward();
    _wheelCtrl.addListener(() {
      setState(() => _wheelAngle = targetAngle * _wheelCtrl.value);
    });
  }

  // ─── Placement de pari (1-tap sur n'importe quelle zone) ──
  Future<void> _bet(String type, {int? number}) async {
    if (_placing || _game?.gameState.phase != 'betting') return;
    final amount = _currentChip;
    final wallet = context.read<WalletProvider>();
    if (wallet.coins < amount) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Solde insuffisant : $amount FCFA requis'),
        backgroundColor: Colors.red, duration: const Duration(seconds: 1)));
      return;
    }

    setState(() => _placing = true);
    try {
      await _svc.placeBet(widget.gameId, type, amount, number: number);
      if (mounted) {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _spinWheel() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    try {
      await _svc.spin(widget.gameId);
      if (mounted) {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _spinning = false);
    }
  }

  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonGreen)),
      );
    }

    final gs = _game!.gameState;
    final wallet = context.watch<WalletProvider>();
    final myPlayer = gs.players[_myId];
    final myTotalBet = myPlayer?.totalBet ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D3B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF062505),
        title: const Text('Roulette', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          // Solde
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 16),
              const SizedBox(width: 4),
              Text('${wallet.coins}',
                  style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          _buildPhaseBar(gs, myTotalBet),
          _buildWheel(gs),
          if (gs.phase == 'betting') ...[
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildBettingTable(myPlayer)),
            _buildSpinButton(myTotalBet),
          ] else if (gs.isFinished)
            Expanded(child: _buildResultBanner(gs)),
        ]),
      ),
    );
  }

  // ─── Barre phase + total mise ─────────────────────────────
  Widget _buildPhaseBar(RouletteGameState gs, int myTotalBet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: gs.phase == 'betting'
          ? AppColors.neonGreen.withValues(alpha: 0.15)
          : gs.phase == 'spinning'
              ? Colors.orange.withValues(alpha: 0.20)
              : AppColors.neonYellow.withValues(alpha: 0.20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            gs.phase == 'betting'
                ? '🎯 Placez vos paris'
                : gs.phase == 'spinning'
                    ? '🌀 La roue tourne...'
                    : 'Résultat : ${gs.result ?? "?"}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
          ),
          if (myTotalBet > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Mise : $myTotalBet FCFA',
                style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Roue (180px, segments rouge/noir/vert) ───────────────
  Widget _buildWheel(RouletteGameState gs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Stack(alignment: Alignment.center, children: [
        Transform.rotate(
          angle: _wheelAngle,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(colors: [
                Colors.green,
                Colors.red, Colors.black, Colors.red, Colors.black,
                Colors.red, Colors.black, Colors.red, Colors.black,
                Colors.red, Colors.black, Colors.red, Colors.black,
                Colors.red, Colors.black, Colors.red, Colors.black,
                Colors.red, Colors.black,
                Colors.green,
              ]),
              border: Border.all(color: AppColors.neonYellow, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 14)
              ],
            ),
          ),
        ),
        // Centre fixe
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
          alignment: Alignment.center,
          child: Text(
            gs.result != null && gs.isFinished ? '${gs.result}' : '?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: gs.result == null
                  ? Colors.black54
                  : gs.result == 0
                      ? Colors.green
                      : (_redNumbers.contains(gs.result)
                          ? Colors.red
                          : Colors.black),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── Table de paris (chips + grille + paris exterieurs) ───
  Widget _buildBettingTable(RoulettePlayer? myPlayer) {
    final myBetsByZone = <String, int>{};
    for (final b in myPlayer?.bets ?? <RouletteBet>[]) {
      final key = b.type == 'number' ? 'n${b.number}' : b.type;
      myBetsByZone[key] = (myBetsByZone[key] ?? 0) + b.amount;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        // Chips selecteur
        _buildChipSelector(),
        const SizedBox(height: 12),

        // Numero 0
        _numberCell(0, myBetsByZone['n0'] ?? 0, fullWidth: true),
        const SizedBox(height: 4),

        // Grille 1-36 (12 lignes × 3 colonnes)
        for (int row = 0; row < 12; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(child: _numberCell(row * 3 + 1, myBetsByZone['n${row * 3 + 1}'] ?? 0)),
              const SizedBox(width: 4),
              Expanded(child: _numberCell(row * 3 + 2, myBetsByZone['n${row * 3 + 2}'] ?? 0)),
              const SizedBox(width: 4),
              Expanded(child: _numberCell(row * 3 + 3, myBetsByZone['n${row * 3 + 3}'] ?? 0)),
            ]),
          ),

        const SizedBox(height: 8),

        // Paris exterieurs (1-18, EVEN, RED, BLACK, ODD, 19-36)
        Row(children: [
          Expanded(child: _outsideBet('1-18', 'low', Colors.teal, myBetsByZone['low'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(child: _outsideBet('PAIR', 'even', Colors.blueGrey, myBetsByZone['even'] ?? 0)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _outsideBet('ROUGE', 'red', Colors.red, myBetsByZone['red'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(child: _outsideBet('NOIR', 'black', Colors.black, myBetsByZone['black'] ?? 0)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _outsideBet('IMPAIR', 'odd', Colors.blueGrey, myBetsByZone['odd'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(child: _outsideBet('19-36', 'high', Colors.orange.shade800, myBetsByZone['high'] ?? 0)),
        ]),

        const SizedBox(height: 12),

        // Aide gains
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Numéro : x35  •  Couleur/Pair/Impair/1-18/19-36 : x2  •  Maison : 10%',
            style: TextStyle(color: Colors.white60, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }

  // ─── Chips selecteur (mise courante) ──────────────────────
  Widget _buildChipSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _chips.map((v) {
          final selected = _currentChip == v;
          final color = v <= 50
              ? Colors.blue
              : v <= 100
                  ? Colors.green
                  : v <= 250
                      ? Colors.orange
                      : v <= 500
                          ? Colors.red
                          : Colors.purple;
          return GestureDetector(
            onTap: () => setState(() => _currentChip = v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  color.withValues(alpha: 0.95),
                  color.withValues(alpha: 0.65),
                ]),
                border: Border.all(
                  color: selected ? AppColors.neonYellow : Colors.white24,
                  width: selected ? 3 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: AppColors.neonYellow.withValues(alpha: 0.5), blurRadius: 10)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$v',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Cellule numero (cliquable, avec chip si pari place) ──
  Widget _numberCell(int n, int betAmount, {bool fullWidth = false}) {
    final isRed = _redNumbers.contains(n);
    final color = n == 0
        ? Colors.green.shade700
        : isRed
            ? Colors.red.shade700
            : Colors.black87;
    return GestureDetector(
      onTap: _placing ? null : () => _bet('number', number: n),
      child: Stack(children: [
        Container(
          height: fullWidth ? 36 : 34,
          width: fullWidth ? double.infinity : null,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
                color: betAmount > 0 ? AppColors.neonYellow : Colors.white12,
                width: betAmount > 0 ? 2 : 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
        if (betAmount > 0) _chipBadge(betAmount),
      ]),
    );
  }

  // ─── Pari exterieur (zone large) ──────────────────────────
  Widget _outsideBet(String label, String type, Color color, int betAmount) {
    return GestureDetector(
      onTap: _placing ? null : () => _bet(type),
      child: Stack(children: [
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
                color: betAmount > 0 ? AppColors.neonYellow : Colors.white12,
                width: betAmount > 0 ? 2 : 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5)),
        ),
        if (betAmount > 0) _chipBadge(betAmount),
      ]),
    );
  }

  // ─── Badge "chip" sur une zone misee ──────────────────────
  Widget _chipBadge(int amount) {
    return Positioned(
      top: 2,
      right: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.neonYellow,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: Text('$amount',
            style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 10)),
      ),
    );
  }

  // ─── Bouton spin ──────────────────────────────────────────
  Widget _buildSpinButton(int myTotalBet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: (_spinning || myTotalBet == 0) ? null : _spinWheel,
          icon: const Icon(Icons.casino, size: 22),
          label: Text(
            myTotalBet == 0 ? 'Place au moins 1 pari' : 'LANCER LA ROUE',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: myTotalBet == 0
                ? Colors.grey.shade700
                : Colors.orange.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  // ─── Bandeau resultat ─────────────────────────────────────
  Widget _buildResultBanner(RouletteGameState gs) {
    final myPlayer = gs.players[_myId];
    final won = myPlayer?.winnings != null && myPlayer!.winnings! > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: won
            ? AppColors.neonGreen.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(won ? '🎉 Gagné !' : '😔 Perdu',
            style: TextStyle(
                color: won ? AppColors.neonGreen : Colors.redAccent,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (won)
          Text(
            // 90% du gain brut (apres 10% maison)
            '+${(myPlayer!.winnings! * 0.9).floor()} FCFA',
            style: TextStyle(
                color: AppColors.neonYellow,
                fontSize: 28,
                fontWeight: FontWeight.w900),
          ),
        const SizedBox(height: 12),
        Text('Numéro tiré : ${gs.result}',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ]),
    );
  }

  // ─── Dialog fin de partie ─────────────────────────────────
  void _showResult() {
    try { context.read<WalletProvider>().refresh(); } catch (_) {}
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final autoTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _rltAutoContinue(ctx);
        });
        return PopScope(
          onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
          child: AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Résultat: ${_game?.gameState.result ?? "?"}',
                style: TextStyle(color: AppColors.neonYellow)),
            content: Text(AppLocalizations.of(context)!.gameNextRound,
                style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () {
                  autoTimer.cancel();
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Text(AppLocalizations.of(context)!.gameQuit,
                    style: TextStyle(color: AppColors.neonRed)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rltAutoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final r = await _svc.autoContinue(widget.gameId);
      if (!mounted) return;
      try { Navigator.pop(ctx); } catch (_) {}
      if (r == 'ended') {
        Navigator.pop(context);
      } else {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        _wheelAngle = 0;
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) {
        try { Navigator.pop(ctx); } catch (_) {}
        Navigator.pop(context);
      }
    }
  }
}
