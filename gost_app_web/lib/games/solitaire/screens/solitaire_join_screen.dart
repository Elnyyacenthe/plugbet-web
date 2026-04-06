// ============================================================
// Solitaire – Rejoindre / créer une salle multijoueur
// ============================================================
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/solitaire_room_models.dart';
import '../services/solitaire_multiplayer_service.dart';
import 'solitaire_create_room_screen.dart';
import 'solitaire_lobby_screen.dart';

class SolitaireJoinScreen extends StatefulWidget {
  const SolitaireJoinScreen({super.key});
  @override
  State<SolitaireJoinScreen> createState() => _SolitaireJoinScreenState();
}

class _SolitaireJoinScreenState extends State<SolitaireJoinScreen> {
  final SolitaireMultiplayerService _service = SolitaireMultiplayerService();
  final TextEditingController _codeController = TextEditingController();
  List<SolitaireRoom> _rooms = [];
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    final rooms = await _service.getPublicRooms();
    if (mounted) setState(() { _rooms = rooms; _loading = false; });
  }

  Future<void> _joinById(String roomId) async {
    if (_joining) return;
    setState(() => _joining = true);
    final room = await _service.joinRoom(roomId);
    setState(() => _joining = false);
    if (!mounted) return;
    if (room != null) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SolitaireLobbyScreen(room: room)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de rejoindre (fonds insuffisants ou salle pleine)')));
    }
  }

  Future<void> _joinByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    if (_joining) return;
    setState(() => _joining = true);
    final room = await _service.joinByCode(code);
    setState(() => _joining = false);
    if (!mounted) return;
    if (room != null) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SolitaireLobbyScreen(room: room)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code invalide ou salle introuvable')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Solitaire Multijoueur',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    IconButton(
                      icon: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.add, color: AppColors.neonGreen, size: 20),
                      ),
                      onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SolitaireCreateRoomScreen()))
                          .then((_) => _loadRooms()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(16),
                  children: [
                    // Code privé
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Code privé',
                              style: TextStyle(color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                textCapitalization: TextCapitalization.characters,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 3),
                                decoration: InputDecoration(
                                  hintText: 'XXXXXX',
                                  hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 2),
                                  filled: true,
                                  fillColor: AppColors.bgElevated,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _joining ? null : _joinByCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonPurple,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _joining
                                  ? SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text('REJOINDRE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),

                    // Salles publiques
                    Row(
                      children: [
                        Text('Salles publiques',
                            style: TextStyle(color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
                          onPressed: _loadRooms,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),

                    if (_loading)
                      Center(child: CircularProgressIndicator(color: AppColors.neonGreen))
                    else if (_rooms.isEmpty)
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.search_off, size: 48,
                                  color: AppColors.textMuted.withValues(alpha: 0.3)),
                              SizedBox(height: 12),
                              Text('Aucune salle disponible',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                              SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => const SolitaireCreateRoomScreen()))
                                    .then((_) => _loadRooms()),
                                icon: Icon(Icons.add),
                                label: Text('Créer une salle'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.neonGreen,
                                  foregroundColor: AppColors.bgDark,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_rooms.length, (i) => _RoomTile(
                            room: _rooms[i],
                            onJoin: () => _joinById(_rooms[i].id),
                            joining: _joining,
                          )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final SolitaireRoom room;
  final VoidCallback onJoin;
  final bool joining;
  const _RoomTile({required this.room, required this.onJoin, required this.joining});

  @override
  Widget build(BuildContext context) {
    final spots = room.maxPlayers - room.currentPlayers;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('🂡', style: TextStyle(fontSize: 20))),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.hostUsername,
                    style: TextStyle(color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700, fontSize: 14)),
                SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.emoji_events, size: 13, color: AppColors.neonYellow),
                  SizedBox(width: 4),
                  Text('${room.betAmount} coins/joueur · ${room.maxPlayers} joueurs',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ],
            ),
          ),
          SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${room.currentPlayers}/${room.maxPlayers}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              SizedBox(height: 4),
              ElevatedButton(
                onPressed: joining ? null : onJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: spots > 0 ? AppColors.neonGreen : AppColors.textMuted,
                  foregroundColor: AppColors.bgDark,
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(spots > 0 ? 'REJOINDRE' : 'PLEIN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
