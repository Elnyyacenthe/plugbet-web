// ============================================================
// LUDO MODULE - Lobby Screen
// Liste des joueurs en ligne, envoi/réception de défis
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/wallet_provider.dart';
import '../models/ludo_models.dart';
import '../providers/ludo_provider.dart';
import 'ludo_game_screen.dart';
import 'ludo_room_screen.dart';

class LudoLobbyScreen extends StatefulWidget {
  const LudoLobbyScreen({super.key});

  @override
  State<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends State<LudoLobbyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ludo = context.read<LudoProvider>();
      ludo.joinLobby();
      ludo.loadPublicRooms();

      // Écouter quand un de nos défis est accepté
      ludo.onGameStarted = (gameId) {
        if (!mounted) return;
        _navigateToGame(gameId);
      };
    });
  }

  @override
  void dispose() {
    // Ne pas quitter le lobby ici si on navigue vers le jeu
    super.dispose();
  }

  void _navigateToGame(String gameId) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LudoGameScreen(gameId: gameId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Ludo Lobby'),
        backgroundColor: AppColors.bgBlueNight,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            context.read<LudoProvider>().leaveLobby();
            Navigator.pop(context);
          },
        ),
        actions: [
          Consumer<LudoProvider>(
            builder: (_, ludo, __) => Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monetization_on,
                      color: AppColors.neonYellow, size: 18),
                  SizedBox(width: 4),
                  Text(
                    '${context.watch<WalletProvider>().coins}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Consumer<LudoProvider>(
          builder: (context, ludo, _) {
            if (ludo.isLoading) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.neonGreen),
                    SizedBox(height: 16),
                    Text(
                      'Connexion au lobby...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await ludo.joinLobby();
                await ludo.loadPublicRooms();
              },
              color: AppColors.neonGreen,
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  // --- Boutons Creer / Rejoindre salle ---
                  _buildRoomActions(context),
                  SizedBox(height: 20),

                  // Défis en attente
                  if (ludo.pendingChallenges.isNotEmpty) ...[
                    _buildSectionTitle(
                      'Defis recus',
                      Icons.notifications_active,
                      AppColors.neonOrange,
                    ),
                    SizedBox(height: 8),
                    ...ludo.pendingChallenges
                        .map((c) => _buildChallengeCard(c, ludo)),
                    SizedBox(height: 20),
                  ],

                  // --- Salles publiques ---
                  if (ludo.publicRooms.isNotEmpty) ...[
                    _buildSectionTitle(
                      'Salles publiques (${ludo.publicRooms.length})',
                      Icons.meeting_room,
                      AppColors.neonBlue,
                    ),
                    SizedBox(height: 8),
                    ...ludo.publicRooms.map((r) => _buildRoomCard(r, ludo)),
                    SizedBox(height: 20),
                  ],

                  // Joueurs en ligne
                  _buildSectionTitle(
                    'Joueurs en ligne (${ludo.onlinePlayers.length})',
                    Icons.people,
                    AppColors.neonGreen,
                  ),
                  SizedBox(height: 8),

                  if (ludo.onlinePlayers.isEmpty)
                    _buildEmptyState()
                  else
                    ...ludo.onlinePlayers.map((p) => _buildPlayerCard(p, ludo)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, color: AppColors.textMuted, size: 48),
          SizedBox(height: 12),
          Text(
            'Aucun joueur en ligne',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tirez vers le bas pour actualiser',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(OnlinePlayer player, LudoProvider ludo) {
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
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.neonBlue.withValues(alpha: 0.2),
            child: Text(
              player.username.isNotEmpty
                  ? player.username[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: AppColors.neonBlue,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          SizedBox(width: 12),

          // Infos joueur
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.username,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '${player.coins} coins',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'En ligne',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bouton Défier
          ElevatedButton(
            onPressed: () => _showChallengeDialog(player, ludo),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Defier',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard(LudoChallenge challenge, LudoProvider ludo) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_kabaddi,
                  color: AppColors.neonOrange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: FutureBuilder<UserProfile?>(
                  future: ludo.getPlayerProfile(challenge.fromUser),
                  builder: (context, snap) {
                    final name = snap.data?.username ?? 'Joueur';
                    return Text(
                      '$name vous defie !',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 16),
              SizedBox(width: 4),
              Text(
                'Mise : ${challenge.betAmount} coins',
                style: TextStyle(
                  color: AppColors.neonYellow,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                'Pot : ${challenge.betAmount * 2} coins',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ludo.declineChallenge(challenge.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.neonRed,
                    side: BorderSide(color: AppColors.neonRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Refuser'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final gameId = await ludo.acceptChallenge(challenge.id);
                    if (gameId != null && mounted) {
                      _navigateToGame(gameId);
                    } else if (ludo.error != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ludo.error!),
                          backgroundColor: AppColors.neonRed,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: AppColors.bgDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Accepter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LudoRoomScreen(isCreating: true),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_circle_outline,
                      color: AppColors.neonGreen, size: 28),
                  SizedBox(height: 6),
                  Text(
                    'Creer une salle',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LudoRoomScreen(isCreating: false),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.neonBlue.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.login_rounded,
                      color: AppColors.neonBlue, size: 28),
                  SizedBox(height: 6),
                  Text(
                    'Rejoindre par code',
                    style: TextStyle(
                      color: AppColors.neonBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomCard(LudoRoom room, LudoProvider ludo) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.meeting_room,
                color: AppColors.neonBlue, size: 22),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.hostUsername ?? 'Salle ${room.code}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '${room.betAmount} coins',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.people, color: AppColors.textMuted, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '${room.currentPlayerCount}/${room.playerCount}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: room.isFull ? null : () async {
              try {
                final gameId = await ludo.joinRoom(room.code);
                if (!mounted) return;
                if (gameId != null) {
                  _navigateToGame(gameId);
                } else {
                  // Salle pas encore pleine → message d'attente
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rejoint ! En attente des autres joueurs...'),
                      backgroundColor: AppColors.neonBlue,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ludo.error ?? e.toString()),
                      backgroundColor: AppColors.neonRed,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              room.isFull ? 'Pleine' : 'Rejoindre',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showChallengeDialog(OnlinePlayer player, LudoProvider ludo) {
    final betController = TextEditingController(text: '50');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.sports_kabaddi, color: AppColors.neonGreen),
            SizedBox(width: 8),
            Text(
              'Defier ${player.username}',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Chips de mise rapide
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [10, 50, 100, 200].map((amount) {
                return GestureDetector(
                  onTap: () => betController.text = '$amount',
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '$amount',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 16),
            TextField(
              controller: betController,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Mise en coins',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                suffixIcon: Icon(Icons.monetization_on,
                    color: AppColors.neonYellow),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.neonGreen),
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Votre solde : ${context.read<WalletProvider>().coins} coins',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Annuler',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final bet = int.tryParse(betController.text) ?? 0;

              if (bet <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Mise invalide')),
                );
                return;
              }
              if (bet > context.read<WalletProvider>().coins) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Solde insuffisant !'),
                    backgroundColor: AppColors.neonRed,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              final challenge =
                  await ludo.sendChallenge(player.userId, bet);
              if (challenge != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Defi envoye a ${player.username} ($bet coins)'),
                    backgroundColor: AppColors.neonGreen,
                  ),
                );
              } else if (ludo.error != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ludo.error!),
                    backgroundColor: AppColors.neonRed,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
            ),
            child: Text(
              'Envoyer le defi',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
