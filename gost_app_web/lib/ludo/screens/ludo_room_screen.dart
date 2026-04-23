import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../providers/ludo_provider.dart';
import 'ludo_game_screen.dart';

class LudoRoomScreen extends StatefulWidget {
  final bool isCreating;

  const LudoRoomScreen({super.key, this.isCreating = true});

  @override
  State<LudoRoomScreen> createState() => _LudoRoomScreenState();
}

class _LudoRoomScreenState extends State<LudoRoomScreen>
    with SingleTickerProviderStateMixin {
  final _betController = TextEditingController(text: '50');
  final _codeController = TextEditingController();
  bool _isPrivate = false;
  int _playerCount = 2; // 2 ou 4 joueurs
  bool _isLoading = false;
  String? _roomCode;
  String? _error;
  Timer? _pollTimer;
  bool _navigated = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    try { context.read<LudoProvider>().onGameStarted = null; } catch (_) {}
    _pulseController.dispose();
    _betController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(widget.isCreating ? 'Creer une salle' : 'Rejoindre'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            final ludo = context.read<LudoProvider>();
            ludo.leaveRoom();
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _roomCode != null
            ? _buildWaitingView()
            : widget.isCreating
                ? _buildCreateView()
                : _buildJoinView(),
      ),
    );
  }

  Widget _buildCreateView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.add_circle_outline,
                  color: AppColors.neonGreen, size: 40),
            ),
          ),
          SizedBox(height: 24),

          Text(
            'Mise en FCFA',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 12),

          // Quick bet chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [10, 50, 100, 200].map((amount) {
              return GestureDetector(
                onTap: () => _betController.text = '$amount',
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    '$amount',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 16),

          TextField(
            controller: _betController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              suffixIcon: Icon(Icons.monetization_on,
                  color: AppColors.neonYellow),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.neonGreen),
              ),
            ),
          ),
          SizedBox(height: 20),

          // Player count selector
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Text(
                      'Nombre de joueurs',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _playerCount = 2),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _playerCount == 2
                                ? AppColors.neonGreen.withValues(alpha: 0.15)
                                : AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _playerCount == 2
                                  ? AppColors.neonGreen
                                  : AppColors.divider,
                              width: _playerCount == 2 ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            '2 Joueurs',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _playerCount == 2
                                  ? AppColors.neonGreen
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _playerCount = 4),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _playerCount == 4
                                ? AppColors.neonGreen.withValues(alpha: 0.15)
                                : AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _playerCount == 4
                                  ? AppColors.neonGreen
                                  : AppColors.divider,
                              width: _playerCount == 4 ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            '4 Joueurs',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _playerCount == 4
                                  ? AppColors.neonGreen
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // Private toggle
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: AppColors.textSecondary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Salle privee',
                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                      Text('Accessible uniquement par code',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v),
                  activeColor: AppColors.neonGreen,
                ),
              ],
            ),
          ),
          SizedBox(height: 24),

          if (_error != null)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.neonRed, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createRoom,
              icon: _isLoading
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                _isLoading ? 'Creation...' : 'Creer la salle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonBlue.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.login_rounded,
                  color: AppColors.neonBlue, size: 40),
            ),
          ),
          SizedBox(height: 24),

          Text(
            'Code de la salle',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 12),

          TextField(
            controller: _codeController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'XXXXXX',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.3),
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.neonBlue),
              ),
            ),
          ),
          SizedBox(height: 24),

          if (_error != null)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.neonRed, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _joinRoom,
              icon: _isLoading
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.login_rounded, size: 24),
              label: Text(
                _isLoading ? 'Connexion...' : 'Rejoindre',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingView() {
    return Consumer<LudoProvider>(
      builder: (context, ludo, _) {
        final room = ludo.currentRoom;
        final currentPlayers = room?.currentPlayerCount ?? 1;
        final totalPlayers = room?.playerCount ?? 2;

        return Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulse animation
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Transform.scale(
                    scale: 0.9 + _pulseController.value * 0.2,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.neonGreen.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppColors.neonGreen.withValues(
                              alpha: 0.3 + _pulseController.value * 0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(Icons.hourglass_top,
                          color: AppColors.neonGreen, size: 44),
                    ),
                  ),
                ),
                SizedBox(height: 32),

                Text(
                  totalPlayers == 2
                      ? 'En attente d\'un adversaire...'
                      : 'En attente des joueurs...',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12),

                // Player count indicator
                Text(
                  '$currentPlayers / $totalPlayers joueurs',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 24),

                // Room code display
                Text(
                  'Code de la salle',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _roomCode!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Code copie !'),
                        backgroundColor: AppColors.neonGreen,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _roomCode!,
                          style: TextStyle(
                            color: AppColors.neonGreen,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.copy, color: AppColors.neonGreen, size: 20),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Partagez ce code avec vos amis',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createRoom() async {
    final bet = int.tryParse(_betController.text) ?? 0;
    if (bet <= 0) {
      setState(() => _error = 'Mise invalide');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ludo = context.read<LudoProvider>();
      final code = await ludo.createRoom(bet, _isPrivate, playerCount: _playerCount);
      if (code != null && mounted) {
        // Écouter quand un adversaire rejoint → naviguer vers le jeu
        ludo.onGameStarted = (gameId) {
          debugPrint('[LUDO-ROOM] onGameStarted callback: $gameId');
          if (mounted && !_navigated) {
            _navigated = true;
            _pollTimer?.cancel();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LudoGameScreen(gameId: gameId)),
            );
          }
        };
        // Fallback : poll toutes les 3s au cas où Realtime rate l'event
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          if (_navigated || !mounted) return;
          final room = ludo.currentRoom;
          if (room != null && room.isFull) {
            // Room pleine → vérifier le game_id en DB
            try {
              final rows = await Supabase.instance.client
                  .from('ludo_rooms')
                  .select('game_id')
                  .eq('id', room.id)
                  .limit(1);
              if (rows.isNotEmpty && rows.first['game_id'] != null && mounted && !_navigated) {
                final gid = rows.first['game_id'] as String;
                debugPrint('[LUDO-ROOM] Poll fallback trouvé gameId=$gid');
                _navigated = true;
                _pollTimer?.cancel();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LudoGameScreen(gameId: gid)),
                );
              }
            } catch (e) {
              debugPrint('[LUDO-ROOM] Poll error: $e');
            }
          }
        });
        setState(() {
          _roomCode = code;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = ludo.error ?? 'Erreur de creation';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Le code doit contenir 6 caracteres');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ludo = context.read<LudoProvider>();
      final gameId = await ludo.joinRoom(code);
      debugPrint('[LUDO-UI] joinRoom retourné: $gameId');
      if (gameId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LudoGameScreen(gameId: gameId)),
        );
      } else if (mounted) {
        // gameId null → salle 4 joueurs pas encore pleine, ou erreur
        if (ludo.error != null) {
          setState(() {
            _error = ludo.error;
            _isLoading = false;
          });
        } else {
          // Rejoint avec succès mais en attente
          setState(() {
            _error = null;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rejoint ! En attente des autres joueurs...'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }
}

