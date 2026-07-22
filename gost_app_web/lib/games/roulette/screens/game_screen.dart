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
import '../../../services/audio_service.dart';

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
    1,
    3,
    5,
    7,
    9,
    12,
    14,
    16,
    18,
    19,
    21,
    23,
    25,
    27,
    30,
    32,
    34,
    36
  };

  static const _chips = [50, 100, 250, 500, 1000];

  @override
  void initState() {
    super.initState();
    _initAudio();
    _wheelCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<MatchesProvider>().pausePolling();
      } catch (_) {}
      try {
        context.read<LiveScoreManager>().pauseTracking();
      } catch (_) {}
    });
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('roulette');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    _pollTimer?.cancel();
    if (_channel != null) _svc.unsubscribe(_channel!);
    try {
      context.read<MatchesProvider>().resumePolling();
    } catch (_) {}
    try {
      context.read<LiveScoreManager>().resumeTracking();
    } catch (_) {}
    AudioService.instance.stopBackgroundMusic();
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
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1)));
      return;
    }

    setState(() => _placing = true);
    try {
      await _svc.placeBet(widget.gameId, type, amount, number: number);
      AudioService.instance.playChipPlace();
      if (mounted) {
        try {
          context.read<WalletProvider>().refresh();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _spinWheel() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    AudioService.instance.playSpin();
    try {
      await _svc.spin(widget.gameId);
      if (mounted) {
        try {
          context.read<WalletProvider>().refresh();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red));
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
        body: Center(
            child: CircularProgressIndicator(color: AppColors.neonGreen)),
      );
    }

    final gs = _game!.gameState;
    final wallet = context.watch<WalletProvider>();
    final myPlayer = gs.players[_myId];
    final myTotalBet = myPlayer?.totalBet ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF06210A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Roulette',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true,
        actions: [
          // Solde — pastille glassy dorée
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(colors: [
                  AppColors.neonYellow.withValues(alpha: 0.18),
                  AppColors.neonYellow.withValues(alpha: 0.06),
                ]),
                border: Border.all(
                    color: AppColors.neonYellow.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonYellow, size: 16),
                const SizedBox(width: 5),
                Text('${wallet.coins}',
                    style: TextStyle(
                        color: AppColors.neonYellow,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ]),
            ),
          ),
        ],
      ),
      body: Container(
        // Tapis de feutre casino (dégradé radial profond)
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.2,
            colors: [
              Color(0xFF1B6B2A),
              Color(0xFF0D3B0F),
              Color(0xFF05170A),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            _buildPhaseBar(gs, myTotalBet),
            _buildWheel(gs),
            if (gs.phase == 'betting') ...[
              Divider(
                  height: 1, color: Colors.white.withValues(alpha: 0.08)),
              Expanded(child: _buildBettingTable(myPlayer)),
              _buildSpinButton(myTotalBet),
            ] else if (gs.isFinished)
              Expanded(child: _buildResultBanner(gs)),
          ]),
        ),
      ),
    );
  }

  // ─── Barre phase + total mise ─────────────────────────────
  Widget _buildPhaseBar(RouletteGameState gs, int myTotalBet) {
    final accent = gs.phase == 'betting'
        ? AppColors.neonGreen
        : gs.phase == 'spinning'
            ? AppColors.neonOrange
            : AppColors.neonYellow;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [
          accent.withValues(alpha: 0.22),
          accent.withValues(alpha: 0.08),
        ]),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              gs.phase == 'betting'
                  ? '🎯 Placez vos paris'
                  : gs.phase == 'spinning'
                      ? '🌀 La roue tourne...'
                      : 'Résultat : ${gs.result ?? "?"}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14),
            ),
          ),
          if (myTotalBet > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: AppColors.neonYellow.withValues(alpha: 0.4)),
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
    final spinning = gs.phase == 'spinning';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SizedBox(
        height: 176,
        child: Stack(alignment: Alignment.center, children: [
          // Halo lumineux derrière la roue
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (spinning
                          ? AppColors.neonOrange
                          : AppColors.neonYellow)
                      .withValues(alpha: 0.35),
                  blurRadius: 34,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          // Roue tournante
          Transform.rotate(
            angle: _wheelAngle,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(colors: [
                  Color(0xFF1B8A2E),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFFD32F2F),
                  Color(0xFF15171C),
                  Color(0xFF1B8A2E),
                ]),
                border: Border.all(color: AppColors.neonYellow, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 14)
                ],
              ),
            ),
          ),
          // Jante metallique doree 3D + studs (couche fixe)
          IgnorePointer(
            child: CustomPaint(
              size: const Size(158, 158),
              painter: _RouletteRimPainter(),
            ),
          ),
          // Anneau intérieur (contour du moyeu)
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [
                Color(0xFF2A3550),
                Color(0xFF0E1A2E),
              ]),
              border: Border.all(
                  color: AppColors.neonYellow.withValues(alpha: 0.6), width: 2),
            ),
          ),
          // Moyeu central (numéro)
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [
                Colors.white,
                Color(0xFFDDE3EC),
              ]),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 8)
              ],
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
                        ? const Color(0xFF1B8A2E)
                        : (_redNumbers.contains(gs.result)
                            ? const Color(0xFFD32F2F)
                            : Colors.black),
              ),
            ),
          ),
          // Aiguille (pointeur haut)
          Positioned(
            top: 4,
            child: CustomPaint(
              size: const Size(22, 20),
              painter: _PointerPainter(color: AppColors.neonYellow),
            ),
          ),
        ]),
      ),
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
              Expanded(
                  child: _numberCell(
                      row * 3 + 1, myBetsByZone['n${row * 3 + 1}'] ?? 0)),
              const SizedBox(width: 4),
              Expanded(
                  child: _numberCell(
                      row * 3 + 2, myBetsByZone['n${row * 3 + 2}'] ?? 0)),
              const SizedBox(width: 4),
              Expanded(
                  child: _numberCell(
                      row * 3 + 3, myBetsByZone['n${row * 3 + 3}'] ?? 0)),
            ]),
          ),

        const SizedBox(height: 8),

        // Paris exterieurs (1-18, EVEN, RED, BLACK, ODD, 19-36)
        Row(children: [
          Expanded(
              child: _outsideBet(
                  '1-18', 'low', Colors.teal, myBetsByZone['low'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(
              child: _outsideBet(
                  'PAIR', 'even', Colors.blueGrey, myBetsByZone['even'] ?? 0)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: _outsideBet(
                  'ROUGE', 'red', Colors.red, myBetsByZone['red'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(
              child: _outsideBet(
                  'NOIR', 'black', Colors.black, myBetsByZone['black'] ?? 0)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: _outsideBet(
                  'IMPAIR', 'odd', Colors.blueGrey, myBetsByZone['odd'] ?? 0)),
          const SizedBox(width: 4),
          Expanded(
              child: _outsideBet('19-36', 'high', Colors.orange.shade800,
                  myBetsByZone['high'] ?? 0)),
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
                    ? [
                        BoxShadow(
                            color: AppColors.neonYellow.withValues(alpha: 0.5),
                            blurRadius: 10)
                      ]
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
    final colors = n == 0
        ? const [Color(0xFF1FA83A), Color(0xFF116522)]
        : isRed
            ? const [Color(0xFFE53935), Color(0xFF9E1B1B)]
            : const [Color(0xFF2C3444), Color(0xFF11151E)];
    final hasBet = betAmount > 0;
    return GestureDetector(
      onTap: _placing ? null : () => _bet('number', number: n),
      child: Stack(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: fullWidth ? 38 : 34,
          width: fullWidth ? double.infinity : null,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
            border: Border.all(
                color: hasBet
                    ? AppColors.neonYellow
                    : Colors.white.withValues(alpha: 0.10),
                width: hasBet ? 2 : 0.5),
            borderRadius: BorderRadius.circular(8),
            boxShadow: hasBet
                ? [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13)),
        ),
        if (hasBet) _chipBadge(betAmount),
      ]),
    );
  }

  // ─── Pari exterieur (zone large) ──────────────────────────
  Widget _outsideBet(String label, String type, Color color, int betAmount) {
    final hasBet = betAmount > 0;
    return GestureDetector(
      onTap: _placing ? null : () => _bet(type),
      child: Stack(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color,
                Color.lerp(color, Colors.black, 0.35) ?? color,
              ],
            ),
            border: Border.all(
                color: hasBet
                    ? AppColors.neonYellow
                    : Colors.white.withValues(alpha: 0.12),
                width: hasBet ? 2 : 0.5),
            borderRadius: BorderRadius.circular(10),
            boxShadow: hasBet
                ? [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.5)),
        ),
        if (hasBet) _chipBadge(betAmount),
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
    final enabled = !(_spinning || myTotalBet == 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.6,
        child: GestureDetector(
          onTap: enabled ? _spinWheel : null,
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: enabled
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFB300), Color(0xFFFF6D00)],
                    )
                  : null,
              color: enabled ? null : Colors.white.withValues(alpha: 0.10),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.neonOrange.withValues(alpha: 0.5),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.casino,
                    size: 22,
                    color: enabled ? Colors.white : Colors.white54),
                const SizedBox(width: 8),
                Text(
                  myTotalBet == 0 ? 'Place au moins 1 pari' : 'LANCER LA ROUE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                    color: enabled ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Bandeau resultat ─────────────────────────────────────
  Widget _buildResultBanner(RouletteGameState gs) {
    final myPlayer = gs.players[_myId];
    final won = myPlayer?.winnings != null && myPlayer!.winnings! > 0;
    final accent = won ? AppColors.neonGreen : AppColors.neonRed;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0E1A2E).withValues(alpha: 0.95),
                accent.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: 3),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(won ? '🎉 Gagné !' : '😔 Perdu',
                style: TextStyle(
                    color: accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                          color: accent.withValues(alpha: 0.6), blurRadius: 14),
                    ])),
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
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text('Numéro tiré : ${gs.result}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── Dialog fin de partie ─────────────────────────────────
  void _showResult() {
    try {
      context.read<WalletProvider>().refresh();
    } catch (_) {}
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      try {
        Navigator.pop(ctx);
      } catch (_) {}
      if (r == 'ended') {
        Navigator.pop(context);
      } else {
        try {
          context.read<WalletProvider>().refresh();
        } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        _wheelAngle = 0;
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) {
        try {
          Navigator.pop(ctx);
        } catch (_) {}
        Navigator.pop(context);
      }
    }
  }
}

// ─── Aiguille (pointeur) de la roue ─────────────────────────
class _PointerPainter extends CustomPainter {
  final Color color;
  const _PointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, size.height) // pointe vers le bas (centre roue)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    // Ombre douce pour le relief
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.6), 3, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Jante metallique doree 3D de la roulette (fixe) ────────
class _RouletteRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final rimMid = r * 0.94;
    final rimW = r * 0.11;

    // Corps de la jante : degrade vertical (lumiere haut / ombre bas) → 3D
    canvas.drawCircle(
      center,
      rimMid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF3C4),
            Color(0xFFE8C05A),
            Color(0xFFB07A00),
            Color(0xFF4A3000),
          ],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(Rect.fromCircle(center: center, radius: rimMid)),
    );
    // Aretes sombres
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF2A1B00);
    canvas.drawCircle(center, rimMid + rimW / 2, edge);
    canvas.drawCircle(center, rimMid - rimW / 2, edge);
    // Reflet haut
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: rimMid),
      -pi * 0.85,
      pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW * 0.35
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // Studs (rivets dores)
    for (int i = 0; i < 16; i++) {
      final a = -pi / 2 + i * 2 * pi / 16;
      final pos = Offset(
          center.dx + rimMid * cos(a), center.dy + rimMid * sin(a));
      canvas.drawCircle(
          pos, 2.4, Paint()..color = const Color(0xFF3A2400));
      canvas.drawCircle(
          pos, 1.6, Paint()..color = const Color(0xFFFFE9A8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
