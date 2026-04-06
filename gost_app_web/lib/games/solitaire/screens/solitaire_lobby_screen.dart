// ============================================================
// Solitaire – Lobby d'attente multijoueur
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';
import '../models/solitaire_room_models.dart';
import '../services/solitaire_multiplayer_service.dart';
import 'solitaire_multiplayer_game_screen.dart';

class SolitaireLobbyScreen extends StatefulWidget {
  final SolitaireRoom room;
  const SolitaireLobbyScreen({super.key, required this.room});
  @override
  State<SolitaireLobbyScreen> createState() => _SolitaireLobbyScreenState();
}

class _SolitaireLobbyScreenState extends State<SolitaireLobbyScreen> {
  final SolitaireMultiplayerService _service = SolitaireMultiplayerService();
  late SolitaireRoom _room;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _service.subscribeToRoom(_room.id, _onRoomUpdate);
    if (_room.status == SolitaireRoomStatus.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToGame());
    }
  }

  void _onRoomUpdate(SolitaireRoom updated) {
    if (!mounted) return;
    setState(() => _room = updated);
    if (updated.status == SolitaireRoomStatus.playing && !_navigated) {
      _goToGame();
    }
  }

  void _goToGame() {
    _navigated = true;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => SolitaireMultiplayerGameScreen(room: _room)));
  }

  Future<void> _leave() async {
    final isHost = _room.hostId == _service.currentUserId;
    if (isHost) {
      await _service.cancelRoom(_room.id);
    }
    _service.unsubscribe();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _service.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _room.maxPlayers - _room.currentPlayers;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                      onPressed: _leave,
                    ),
                    Expanded(
                      child: Text('Lobby – Solitaire',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 48),
                  ],
                ),
                SizedBox(height: 20),

                // Code privé
                if (_room.isPrivate && _room.privateCode != null)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _room.privateCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Code copié !')));
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      margin: EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.neonPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.vpn_key, color: AppColors.neonPurple, size: 18),
                          SizedBox(width: 8),
                          Text('Code : ${_room.privateCode}',
                              style: TextStyle(
                                  color: AppColors.neonPurple,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  letterSpacing: 4)),
                          SizedBox(width: 8),
                          Icon(Icons.copy, color: AppColors.neonPurple, size: 16),
                        ],
                      ),
                    ),
                  ),

                // Infos partie
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _InfoChip(Icons.people, '${_room.currentPlayers}/${_room.maxPlayers}',
                          AppColors.neonBlue, 'Joueurs'),
                      _InfoChip(Icons.monetization_on, '${_room.betAmount}',
                          AppColors.neonYellow, 'Mise'),
                      _InfoChip(Icons.emoji_events, '${_room.pot}',
                          AppColors.neonGreen, 'Pot'),
                    ],
                  ),
                ),
                SizedBox(height: 20),

                // Liste joueurs
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Joueurs connectés',
                      style: TextStyle(color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      // Joueurs présents
                      ..._room.players.map((p) => _PlayerTile(
                            username: p.username,
                            isHost: p.id == _room.hostId,
                            isReady: true,
                          )),
                      // Slots vides
                      ...List.generate(
                        waiting,
                        (_) => const _PlayerTile(
                          username: null,
                          isHost: false,
                          isReady: false,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),
                if (_room.status == SolitaireRoomStatus.waiting)
                  Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.neonGreen),
                      SizedBox(height: 12),
                      Text(
                        waiting > 0
                            ? 'En attente de $waiting joueur${waiting > 1 ? 's' : ''}...'
                            : 'Lancement de la partie...',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final String label;
  const _InfoChip(this.icon, this.value, this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        SizedBox(height: 4),
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final String? username;
  final bool isHost;
  final bool isReady;
  const _PlayerTile({this.username, required this.isHost, required this.isReady});

  @override
  Widget build(BuildContext context) {
    final initials = (username?.isNotEmpty == true) ? username![0].toUpperCase() : '?';
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isReady
            ? AppColors.neonGreen.withValues(alpha: 0.05)
            : AppColors.bgCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady
              ? AppColors.neonGreen.withValues(alpha: 0.25)
              : AppColors.divider.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady
                  ? const Color(0xFF9C27B0).withValues(alpha: 0.2)
                  : AppColors.bgCard,
              border: Border.all(
                color: isReady
                    ? const Color(0xFF9C27B0).withValues(alpha: 0.5)
                    : AppColors.divider,
              ),
            ),
            child: Center(
              child: Text(initials,
                  style: TextStyle(
                    color: isReady ? AppColors.textPrimary : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  )),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              username ?? 'En attente...',
              style: TextStyle(
                color: isReady ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: isReady ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (isHost)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.neonOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('HÔTE',
                  style: TextStyle(
                      color: AppColors.neonOrange,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            )
          else if (isReady)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('PRÊT',
                  style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
