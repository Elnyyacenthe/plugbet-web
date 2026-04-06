// ============================================================
// Checkers – Créer une room (mise configurable)
// ============================================================
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../services/checkers_service.dart';
import 'lobby_screen.dart';

class CreateCheckersRoomScreen extends StatefulWidget {
  const CreateCheckersRoomScreen({super.key});
  @override
  State<CreateCheckersRoomScreen> createState() => _CreateCheckersRoomScreenState();
}

class _CreateCheckersRoomScreenState extends State<CreateCheckersRoomScreen> {
  final CheckersService _service = CheckersService();
  bool _isPrivate = false;
  bool _creating = false;
  int _coins = 0;
  int _selectedBet = 100;

  static const List<int> _betOptions = [50, 100, 200, 500];

  @override
  void initState() {
    super.initState();
    _service.getCoins().then((c) => setState(() => _coins = c));
  }

  Future<void> _create() async {
    if (_coins < _selectedBet) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fonds insuffisants ($_selectedBet coins requis)')));
      return;
    }
    setState(() => _creating = true);
    final room = await _service.createRoom(betAmount: _selectedBet, isPrivate: _isPrivate);
    setState(() => _creating = false);
    if (room != null && mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => CheckersLobbyScreen(room: room)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création de la room')));
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
              Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Créer une partie',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.neonOrange.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.4), width: 2),
                          ),
                          child: Icon(Icons.grid_on, color: AppColors.neonOrange, size: 36),
                        ),
                      ),
                      SizedBox(height: 24),

                      // ── Sélecteur de mise ─────────────────────────────
                      Text('Mise d\'entrée',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              letterSpacing: 0.5)),
                      SizedBox(height: 10),
                      Row(
                        children: _betOptions.map((bet) {
                          final selected = _selectedBet == bet;
                          final canAfford = _coins >= bet;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedBet = bet),
                              child: Container(
                                margin: EdgeInsets.only(right: 8),
                                padding: EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.neonOrange.withValues(alpha: 0.2)
                                      : AppColors.bgCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.neonOrange
                                        : canAfford
                                            ? AppColors.divider
                                            : AppColors.neonRed.withValues(alpha: 0.3),
                                    width: selected ? 1.5 : 0.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$bet',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? AppColors.neonOrange
                                            : canAfford
                                                ? AppColors.textPrimary
                                                : AppColors.textMuted,
                                      ),
                                    ),
                                    Text(
                                      'coins',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: selected
                                            ? AppColors.neonOrange.withValues(alpha: 0.7)
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 16),

                      // ── Infos ──────────────────────────────────────────
                      _infoTile(
                        Icons.emoji_events,
                        AppColors.neonYellow,
                        'Pot total',
                        '${_selectedBet * 2} coins',
                      ),
                      SizedBox(height: 10),
                      _infoTile(
                        Icons.account_balance_wallet_outlined,
                        _coins >= _selectedBet ? AppColors.neonGreen : AppColors.neonRed,
                        'Votre solde',
                        '$_coins coins',
                      ),
                      SizedBox(height: 10),

                      // ── Room privée ────────────────────────────────────
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: AppColors.neonPurple),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('Room privée',
                                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            ),
                            Switch(
                              value: _isPrivate,
                              onChanged: (v) => setState(() => _isPrivate = v),
                              activeColor: AppColors.neonPurple,
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_creating || _coins < _selectedBet) ? null : _create,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.neonOrange,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: AppColors.neonOrange.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _creating
                              ? CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                              : Text('CRÉER – $_selectedBet coins',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, Color color, String label, String value) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }
}
