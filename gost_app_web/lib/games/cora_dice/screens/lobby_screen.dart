// ============================================================
// CORA DICE - Lobby (Salle d'attente)
// Affiche joueurs, ready check, chat, démarre partie
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../models/cora_models.dart';
import '../services/cora_service.dart';
import 'game_screen.dart';

class CoraLobbyScreen extends StatefulWidget {
  final String roomId;

  const CoraLobbyScreen({super.key, required this.roomId});

  @override
  State<CoraLobbyScreen> createState() => _CoraLobbyScreenState();
}

class _CoraLobbyScreenState extends State<CoraLobbyScreen> {
  final CoraService _service = CoraService();
  CoraRoom? _room;
  List<Map<String, dynamic>> _players = [];
  List<CoraMessage> _messages = [];
  bool _isReady = false;
  bool _isLoading = true;

  RealtimeChannel? _roomChannel;
  RealtimeChannel? _playersChannel;
  RealtimeChannel? _messagesChannel;

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRoom();
    _loadPlayers();
    _loadMessages();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    if (_roomChannel != null) _service.unsubscribe(_roomChannel!);
    if (_playersChannel != null) _service.unsubscribe(_playersChannel!);
    if (_messagesChannel != null) _service.unsubscribe(_messagesChannel!);
    super.dispose();
  }

  Future<void> _loadRoom() async {
    _room = await _service.getRoom(widget.roomId);
    setState(() => _isLoading = false);
  }

  Future<void> _loadPlayers() async {
    try {
      final data = await Supabase.instance.client
          .from('cora_room_players')
          .select()
          .eq('room_id', widget.roomId)
          .order('joined_at');
      setState(() => _players = List<Map<String, dynamic>>.from(data));

      // Vérifier si je suis prêt
      final myId = _service.currentUserId;
      final me = _players.firstWhere(
        (p) => p['user_id'] == myId,
        orElse: () => {},
      );
      if (me.isNotEmpty) {
        setState(() => _isReady = me['is_ready'] as bool? ?? false);
      }
    } catch (e) {
      debugPrint('Erreur loadPlayers: $e');
    }
  }

  Future<void> _loadMessages() async {
    _messages = await _service.getMessages(widget.roomId);
    setState(() {});
    _scrollToBottom();
  }

  void _subscribeToUpdates() {
    // Room updates
    _roomChannel = _service.subscribeRoom(widget.roomId, (room) {
      setState(() => _room = room);

      // Si partie démarrée, naviguer vers le jeu
      if (room.status == CoraRoomStatus.playing && room.gameId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CoraGameScreen(gameId: room.gameId!),
          ),
        );
      }
    });

    // Players updates
    _playersChannel = Supabase.instance.client
        .channel('cora-players-${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cora_room_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (_) => _loadPlayers(),
        )
        .subscribe();

    // Messages (avec dédup par ID)
    _messagesChannel = _service.subscribeMessages(widget.roomId, (msg) {
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _room == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Salle d\'attente', style: TextStyle(fontSize: 16)),
            Text(
              'Code: ${_room!.code}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.neonGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => _confirmExit(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _room!.code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Code copié !'),
                  backgroundColor: AppColors.neonGreen,
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxHeight < 600;
          return Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // Info pot (compact sur petit écran)
                _buildPotInfo(),

                // Grille des joueurs
                Expanded(
                  flex: 2,
                  child: _buildPlayersGrid(),
                ),

                // Chat (masqué sur très petit écran)
                if (!isSmall)
                  Expanded(
                    flex: 1,
                    child: _buildChat(),
                  ),

                // Bouton ready
                _buildReadyButton(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPotInfo() {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.neonYellow.withValues(alpha: 0.2),
            Colors.orange.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _infoItem(Icons.people, '${_players.length}/${_room!.playerCount}',
              'Joueurs'),
          _infoItem(Icons.monetization_on, '${_room!.potAmount}', 'Pot total'),
          _infoItem(Icons.casino, '${_room!.betAmount}', 'Mise'),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.neonYellow, size: 24),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayersGrid() {
    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: _room!.playerCount,
      itemBuilder: (context, index) {
        if (index < _players.length) {
          return _buildPlayerCard(_players[index]);
        } else {
          return _buildEmptySlot();
        }
      },
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final username = player['username'] as String;
    final isReady = player['is_ready'] as bool? ?? false;
    final isMe = player['user_id'] == _service.currentUserId;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: isMe
            ? LinearGradient(
                colors: [
                  AppColors.neonGreen.withValues(alpha: 0.2),
                  AppColors.neonBlue.withValues(alpha: 0.2),
                ],
              )
            : AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? AppColors.neonGreen
              : AppColors.divider.withValues(alpha: 0.3),
          width: isMe ? 2 : 1,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor:
                isReady ? AppColors.neonGreen : AppColors.bgElevated,
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: TextStyle(
                color: isReady ? AppColors.bgDark : AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(height: 4),

          // Nom
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? AppColors.neonGreen : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2),

          // Statut
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isReady
                  ? AppColors.neonGreen.withValues(alpha: 0.2)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isReady ? Icons.check_circle : Icons.schedule,
                  color: isReady ? AppColors.neonGreen : AppColors.textMuted,
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  isReady ? 'Prêt' : 'En attente',
                  style: TextStyle(
                    color: isReady ? AppColors.neonGreen : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_add_outlined,
            size: 40,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          SizedBox(height: 8),
          Text(
            'En attente...',
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Header compact
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: AppColors.neonBlue, size: 16),
                SizedBox(width: 6),
                Text(
                  'Chat',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Aucun message',
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.userId == _service.currentUserId;
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
          ),

          // Input
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: AppColors.neonGreen),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CoraMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.neonGreen.withValues(alpha: 0.2)
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                msg.username,
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              msg.message,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyButton() {
    final allReady =
        _players.length == _room!.playerCount &&
        _players.every((p) => p['is_ready'] as bool? ?? false);

    return Container(
      padding: EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: allReady ? null : _toggleReady,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isReady ? AppColors.neonRed : AppColors.neonGreen,
            foregroundColor: AppColors.bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            allReady
                ? 'Démarrage...'
                : _isReady
                    ? 'Annuler'
                    : 'PRÊT !',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    await _service.sendMessage(widget.roomId, text);
    _messageController.clear();
  }

  Future<void> _toggleReady() async {
    HapticFeedback.heavyImpact();
    final newReady = !_isReady;
    await _service.markReady(widget.roomId, newReady);
    setState(() => _isReady = newReady);

    // Si tous prêts → démarrer la partie (le dernier à appuyer PRÊT lance)
    if (newReady) {
      // Petit délai pour que le Realtime synchronise
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadPlayers();
      final allReady = _players.length == _room!.playerCount &&
          _players.every((p) => p['is_ready'] as bool? ?? false);
      if (allReady && mounted) {
        debugPrint('[CORA-LOBBY] Tous prêts, démarrage...');
        final gameId = await _service.startGame(widget.roomId);
        debugPrint('[CORA-LOBBY] gameId: $gameId');
        if (gameId != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => CoraGameScreen(gameId: gameId)),
          );
        }
      }
    }
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Quitter la salle?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Voulez-vous vraiment quitter cette salle?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Quitter',
                style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}
