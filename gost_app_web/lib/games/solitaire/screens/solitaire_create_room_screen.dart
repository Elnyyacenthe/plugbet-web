// ============================================================
// Solitaire – Créer une salle multijoueur
// ============================================================
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../services/solitaire_multiplayer_service.dart';
import 'solitaire_lobby_screen.dart';

class SolitaireCreateRoomScreen extends StatefulWidget {
  const SolitaireCreateRoomScreen({super.key});
  @override
  State<SolitaireCreateRoomScreen> createState() => _SolitaireCreateRoomScreenState();
}

class _SolitaireCreateRoomScreenState extends State<SolitaireCreateRoomScreen> {
  final SolitaireMultiplayerService _service = SolitaireMultiplayerService();
  int _selectedPlayers = 2;
  int _selectedBet = 100;
  bool _isPrivate = false;
  bool _creating = false;
  int _coins = 0;

  static const List<int> _playerOptions = [2, 3, 4];
  static const List<int> _betOptions = [50, 100, 200, 500];

  @override
  void initState() {
    super.initState();
    _service.getCoins().then((c) => setState(() => _coins = c));
  }

  Future<void> _create() async {
    if (_coins < _selectedBet) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fonds insuffisants ($_selectedBet FCFA requis)')));
      return;
    }
    setState(() => _creating = true);
    final room = await _service.createRoom(
      betAmount: _selectedBet,
      maxPlayers: _selectedPlayers,
      isPrivate: _isPrivate,
    );
    setState(() => _creating = false);
    if (!mounted) return;
    if (room != null) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => SolitaireLobbyScreen(room: room)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création')));
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
                      child: Text('Nouvelle partie',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(20),
                  children: [
                    SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF9C27B0).withValues(alpha: 0.5), width: 2),
                        ),
                        child: Center(child: Text('🂡', style: TextStyle(fontSize: 34))),
                      ),
                    ),
                    SizedBox(height: 28),

                    // Nombre de joueurs
                    Text('Nombre de joueurs',
                        style: TextStyle(color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)),
                    SizedBox(height: 10),
                    Row(
                      children: _playerOptions.map((n) {
                        final selected = _selectedPlayers == n;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedPlayers = n),
                            child: Container(
                              margin: EdgeInsets.only(right: 8),
                              padding: EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.neonGreen.withValues(alpha: 0.15)
                                    : AppColors.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? AppColors.neonGreen : AppColors.divider,
                                  width: selected ? 1.5 : 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text('$n',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: selected ? AppColors.neonGreen : AppColors.textPrimary,
                                      )),
                                  Text('joueurs',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: selected
                                            ? AppColors.neonGreen.withValues(alpha: 0.7)
                                            : AppColors.textMuted,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),

                    // Mise
                    Text('Mise par joueur',
                        style: TextStyle(color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.5)),
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
                                    ? AppColors.neonYellow.withValues(alpha: 0.12)
                                    : AppColors.bgCard,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.neonYellow
                                      : canAfford
                                          ? AppColors.divider
                                          : AppColors.neonRed.withValues(alpha: 0.3),
                                  width: selected ? 1.5 : 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text('$bet',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? AppColors.neonYellow
                                            : canAfford
                                                ? AppColors.textPrimary
                                                : AppColors.textMuted,
                                      )),
                                  Text('coins',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: selected
                                            ? AppColors.neonYellow.withValues(alpha: 0.7)
                                            : AppColors.textMuted,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),

                    // Récap pot
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.emoji_events, color: AppColors.neonYellow, size: 18),
                            SizedBox(width: 8),
                            Text('Pot total', style: TextStyle(color: AppColors.textSecondary)),
                          ]),
                          Text('${_selectedBet * _selectedPlayers} FCFA',
                              style: TextStyle(color: AppColors.neonYellow,
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                    ),
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                color: _coins >= _selectedBet ? AppColors.neonGreen : AppColors.neonRed,
                                size: 18),
                            SizedBox(width: 8),
                            Text('Votre solde', style: TextStyle(color: AppColors.textSecondary)),
                          ]),
                          Text('$_coins FCFA',
                              style: TextStyle(
                                color: _coins >= _selectedBet ? AppColors.neonGreen : AppColors.neonRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              )),
                        ],
                      ),
                    ),
                    SizedBox(height: 14),

                    // Room privée
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
                                  style: TextStyle(color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600))),
                          Switch(
                            value: _isPrivate,
                            onChanged: (v) => setState(() => _isPrivate = v),
                            activeColor: AppColors.neonPurple,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: (_creating || _coins < _selectedBet) ? null : _create,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonGreen,
                          foregroundColor: AppColors.bgDark,
                          disabledBackgroundColor: AppColors.neonGreen.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _creating
                            ? CircularProgressIndicator(color: AppColors.bgDark, strokeWidth: 2)
                            : Text('CRÉER – $_selectedBet FCFA',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    SizedBox(height: 20),
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
