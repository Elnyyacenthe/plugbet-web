// ============================================================
// CORA DICE - Écran principal
// Liste des parties + création + join + vérification solde
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../models/cora_models.dart';
import '../services/cora_service.dart';
import 'create_room_screen.dart';
import 'lobby_screen.dart';

class CoraDiceScreen extends StatefulWidget {
  const CoraDiceScreen({super.key});

  @override
  State<CoraDiceScreen> createState() => _CoraDiceScreenState();
}

class _CoraDiceScreenState extends State<CoraDiceScreen> {
  final CoraService _service = CoraService();
  final _codeController = TextEditingController();

  List<CoraRoom> _publicRooms = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletProvider>().refresh();
    });
    _service.cleanupStaleRooms(); // Nettoyer les salles > 1h
    await _loadPublicRooms();
  }

  Future<void> _loadPublicRooms() async {
    setState(() => _isLoading = true);
    _publicRooms = await _service.getPublicRooms();
    setState(() => _isLoading = false);
  }

  void _navigateToLobby(String roomId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CoraLobbyScreen(roomId: roomId)),
    ).then((_) {
      _loadData(); // Recharger après retour
    });
  }

  Future<void> _joinRoom(String code, int betAmount) async {
    final coins = context.read<WalletProvider>().coins;
    if (coins < betAmount) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Solde insuffisant ! Vous avez $coins coins, il faut $betAmount coins.',
            ),
            backgroundColor: AppColors.neonRed,
          ),
        );
      }
      return;
    }

    try {
      final roomId = await _service.joinRoom(code);
      if (roomId != null && mounted) {
        _navigateToLobby(roomId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.neonRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header avec solde (réduit sur petit écran)
              if (!isSmallScreen) _buildHeader(isSmallScreen)
              else _buildCompactHeader(),

              // Boutons d'action
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildCreateButton()),
                    SizedBox(width: 12),
                    Expanded(child: _buildJoinButton()),
                  ],
                ),
              ),

              // Liste des rooms publiques
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.neonGreen,
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.neonGreen,
                          ),
                        )
                      : _publicRooms.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                              itemCount: _publicRooms.length,
                              itemBuilder: (context, index) {
                                return _buildRoomCard(_publicRooms[index], isSmallScreen);
                              },
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    final headerPadding = isSmallScreen ? 12.0 : 16.0;
    final iconSize = isSmallScreen ? 60.0 : 80.0;
    final titleSize = isSmallScreen ? 24.0 : 32.0;

    return Container(
      padding: EdgeInsets.all(headerPadding),
      child: Column(
        children: [
          // Bouton retour
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Retour',
              ),
              const Spacer(),
            ],
          ),

          // Logo dés
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.neonGreen.withValues(alpha: 0.3),
                  Colors.orange.withValues(alpha: 0.3),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.neonGreen, width: 3),
            ),
            child: Icon(
              Icons.casino,
              color: AppColors.neonGreen,
              size: iconSize * 0.5,
            ),
          ),
          SizedBox(height: isSmallScreen ? 8 : 12),

          // Titre
          Text(
            'CORA DICE',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),

          // Sous-titre
          if (!isSmallScreen) ...[
            SizedBox(height: 4),
            Text(
              'Jeu de dés camerounais • Virtual Coins',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],

          // Solde
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => Padding(
              padding: EdgeInsets.only(top: isSmallScreen ? 8 : 12),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.neonYellow.withValues(alpha: 0.2),
                      AppColors.neonGreen.withValues(alpha: 0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet,
                        color: AppColors.neonYellow, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '${wallet.coins} coins',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Icon(Icons.casino, color: AppColors.neonGreen, size: 22),
          const SizedBox(width: 8),
          Text('CORA DICE', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900,
            color: AppColors.textPrimary, letterSpacing: 1,
          )),
          const Spacer(),
          Consumer<WalletProvider>(
            builder: (_, wallet, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${wallet.coins} coins', style: TextStyle(
                color: AppColors.neonYellow, fontSize: 13, fontWeight: FontWeight.w800,
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateCoraRoomScreen()),
        );
        if (result != null && mounted) {
          _navigateToLobby(result as String);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.neonGreen, Color(0xFF2ECC71)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonGreen.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.bgDark, size: 22),
            SizedBox(width: 8),
            Text(
              'Créer',
              style: TextStyle(
                color: AppColors.bgDark,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _showJoinDialog();
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withValues(alpha: 0.8),
              Colors.deepOrange.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.login, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Rejoindre',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(CoraRoom room, bool isSmallScreen) {
    final coins = context.watch<WalletProvider>().coins;
    final canAfford = coins >= room.betAmount;

    return Container(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icône dé
          Container(
            width: isSmallScreen ? 44 : 50,
            height: isSmallScreen ? 44 : 50,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.casino,
              color: AppColors.neonGreen,
              size: isSmallScreen ? 24 : 28,
            ),
          ),
          SizedBox(width: isSmallScreen ? 10 : 14),

          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.hostUsername ?? 'Salle ${room.code}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isSmallScreen ? 2 : 4),
                Row(
                  children: [
                    Icon(Icons.people,
                        color: AppColors.textSecondary,
                        size: isSmallScreen ? 12 : 14),
                    SizedBox(width: isSmallScreen ? 3 : 4),
                    Text(
                      '${room.playerCount}J',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: isSmallScreen ? 11 : 12,
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow,
                        size: isSmallScreen ? 12 : 14),
                    SizedBox(width: isSmallScreen ? 3 : 4),
                    Flexible(
                      child: Text(
                        '${room.betAmount}',
                        style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: isSmallScreen ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bouton rejoindre
          ElevatedButton(
            onPressed: canAfford
                ? () {
                    HapticFeedback.lightImpact();
                    _joinRoom(room.code, room.betAmount);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canAfford ? AppColors.neonGreen : AppColors.bgElevated,
              foregroundColor: canAfford ? AppColors.bgDark : AppColors.textMuted,
              disabledBackgroundColor: AppColors.bgElevated,
              disabledForegroundColor: AppColors.textMuted,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 6 : 8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              canAfford ? 'Join' : 'Solde',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isSmallScreen ? 12 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.casino_outlined,
            size: 80,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16),
          Text(
            'Aucune partie publique',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Créez une partie ou rejoignez par code',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.login, color: Colors.orange),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                'Rejoindre par code',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'XXXXXX',
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.orange, width: 2),
                ),
              ),
            ),
            ...[
              SizedBox(height: 12),
              Consumer<WalletProvider>(
                builder: (_, wallet, __) => Text(
                  'Votre solde : ${wallet.coins} coins',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = _codeController.text.trim();
              if (code.length < 6) {
                return;
              }
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();

              // Récupérer la room pour connaître la mise
              try {
                final rooms = await _service.getPublicRooms();
                final room = rooms.cast<CoraRoom?>().firstWhere(
                      (r) => r?.code == code,
                      orElse: () => null,
                    );

                final betAmount = room?.betAmount ?? 200;
                _codeController.clear();
                await _joinRoom(code, betAmount);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: AppColors.neonRed,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Rejoindre',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
