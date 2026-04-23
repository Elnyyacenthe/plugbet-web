// ============================================================
// Checkers – Écran principal (hub)
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../services/checkers_service.dart';
import '../models/checkers_models.dart';
import 'create_room_screen.dart';
import 'lobby_screen.dart';

class CheckersScreen extends StatefulWidget {
  const CheckersScreen({super.key});
  @override
  State<CheckersScreen> createState() => _CheckersScreenState();
}

class _CheckersScreenState extends State<CheckersScreen> {
  final CheckersService _service = CheckersService();
  bool _loading = true;
  List<CheckersRoom> _rooms = [];

  @override
  void initState() {
    super.initState();
    _service.cleanupStaleRooms(); // Nettoyer les salles > 1h
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    context.read<WalletProvider>().refresh();
    final rooms = await _service.getPublicRooms();
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: uid == null ? _buildLoginPrompt() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: AppColors.neonOrange),
            SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.gameConnectRequired,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.gameConnectToPlay,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.neonOrange,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Bouton retour
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          SizedBox(height: 4),
          _buildHeader(),
          SizedBox(height: 20),
          _buildActionButtons(),
          SizedBox(height: 24),
          _buildRoomsList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.neonOrange.withValues(alpha: 0.2), AppColors.bgCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.neonOrange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.grid_on, color: AppColors.neonOrange, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<WalletProvider>(
                  builder: (_, wallet, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.gameHello(wallet.username.isNotEmpty ? wallet.username : 'Player'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 18),
                        SizedBox(width: 4),
                        Text('${wallet.coins} FCFA',
                            style: TextStyle(fontSize: 14, color: AppColors.neonYellow, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(onPressed: _load, icon: Icon(Icons.refresh, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            label: 'CRÉER',
            icon: Icons.add_circle_outline,
            color: AppColors.neonOrange,
            onTap: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CreateCheckersRoomScreen()));
              if (result == true) _load();
            },
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            label: 'REJOINDRE',
            icon: Icons.vpn_key_outlined,
            color: AppColors.neonBlue,
            onTap: _showJoinByCodeDialog,
          ),
        ),
      ],
    );
  }

  void _showJoinByCodeDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.gameRoomCodeTitle, style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: AppColors.textPrimary, letterSpacing: 4, fontSize: 20),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'XXXXXX',
            hintStyle: TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.bgElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.commonCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonBlue),
            onPressed: () async {
              final code = ctrl.text.trim().toUpperCase();
              if (code.length < 6) return;
              Navigator.pop(context);
              final room = await _service.joinByCode(code);
              if (room != null && mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => CheckersLobbyScreen(room: room)));
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context)!.gameRoomNotFound)));
              }
            },
            child: Text(AppLocalizations.of(context)!.gameJoin),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.gamePublicRooms,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        SizedBox(height: 12),
        if (_loading)
          Center(child: CircularProgressIndicator(color: AppColors.neonOrange))
        else if (_rooms.isEmpty)
          Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.sports_esports_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.4)),
                  SizedBox(height: 12),
                  Text(AppLocalizations.of(context)!.gameNoRoomsAvailable, style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(height: 4),
                  Text(AppLocalizations.of(context)!.gameCreateRoomPrompt, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          ..._rooms.map((r) => _RoomTile(
                room: r,
                onJoin: () async {
                  final joined = await _service.joinRoom(r.id);
                  if (joined != null && mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CheckersLobbyScreen(room: joined)));
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(context)!.gameRoomJoinFailed)));
                  }
                },
              )),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
        ]),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final CheckersRoom room;
  final VoidCallback onJoin;
  const _RoomTile({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.neonOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.grid_on, color: AppColors.neonOrange, size: 22),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(room.hostUsername, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Row(children: [
                Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 13),
                SizedBox(width: 3),
                Text('Mise : ${room.betAmount} FCFA', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ]),
            ]),
          ),
          ElevatedButton(
            onPressed: onJoin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonOrange,
              foregroundColor: Colors.black,
              minimumSize: const Size(80, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Rejoindre', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
