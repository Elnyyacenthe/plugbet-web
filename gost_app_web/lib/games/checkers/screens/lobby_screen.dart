// ============================================================
// Checkers – Lobby (attente adversaire)
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/checkers_models.dart';
import '../services/checkers_service.dart';
import 'game_screen.dart';

class CheckersLobbyScreen extends StatefulWidget {
  final CheckersRoom room;
  const CheckersLobbyScreen({super.key, required this.room});
  @override
  State<CheckersLobbyScreen> createState() => _CheckersLobbyScreenState();
}

class _CheckersLobbyScreenState extends State<CheckersLobbyScreen> {
  final CheckersService _service = CheckersService();
  late CheckersRoom _room;
  bool _navigated = false;

  // Chat
  List<Map<String, dynamic>> _messages = [];
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _service.subscribeToRoom(_room.id, _onRoomUpdate);
    _loadMessages();
    _subscribeMessages();

    // Si la partie est déjà en cours (guest vient de rejoindre)
    if (_room.status == CheckersRoomStatus.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToGame());
    }
  }

  Future<void> _loadMessages() async {
    final msgs = await _service.getMessages(_room.id);
    if (mounted) setState(() => _messages = msgs);
    _scrollToBottom();
  }

  void _subscribeMessages() {
    _messagesChannel = _service.subscribeMessages(_room.id, (msg) {
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await _service.sendMessage(_room.id, text);
  }

  void _onRoomUpdate(CheckersRoom updated) {
    if (!mounted) return;
    setState(() => _room = updated);
    if (updated.status == CheckersRoomStatus.playing && !_navigated) {
      _goToGame();
    }
  }

  void _goToGame() {
    _navigated = true;
    final uid = _service.currentUserId ?? '';
    final myColor = _room.hostId == uid
        ? (_room.hostColor == 'red' ? PieceColor.red : PieceColor.black)
        : (_room.hostColor == 'red' ? PieceColor.black : PieceColor.red);
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => CheckersGameScreen(room: _room, myColor: myColor)));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    _service.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUserId;
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
                      icon: Icon(Icons.arrow_back_ios_new,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Lobby – Dames',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 48),
                  ],
                ),
                SizedBox(height: 12),

                // Code privé
                if (_room.isPrivate && _room.privateCode != null)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: _room.privateCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context)!.gameCodeCopied)));
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.neonPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                AppColors.neonPurple.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.vpn_key,
                              color: AppColors.neonPurple, size: 16),
                          SizedBox(width: 8),
                          Text('Code : ${_room.privateCode}',
                              style: TextStyle(
                                  color: AppColors.neonPurple,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  letterSpacing: 4)),
                          SizedBox(width: 8),
                          Icon(Icons.copy,
                              color: AppColors.neonPurple, size: 14),
                        ],
                      ),
                    ),
                  ),

                // Joueurs
                Row(
                  children: [
                    Expanded(child: _PlayerCard(
                      username: _room.hostUsername,
                      pieceColor: _room.hostColor ?? 'red',
                      isReady: true,
                      label: 'Hôte',
                    )),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(AppLocalizations.of(context)!.gameVs,
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w900,
                              fontSize: 20)),
                    ),
                    Expanded(child: _PlayerCard(
                      username: _room.guestUsername,
                      pieceColor:
                          _room.hostColor == 'red' ? 'black' : 'red',
                      isReady: _room.guestId != null,
                      label: 'Invité',
                    )),
                  ],
                ),
                SizedBox(height: 12),

                // Pot
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.emoji_events,
                          color: AppColors.neonYellow, size: 18),
                      SizedBox(width: 8),
                      Text('Pot : ${_room.betAmount * 2} FCFA',
                          style: TextStyle(
                              color: AppColors.neonYellow,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ],
                  ),
                ),
                SizedBox(height: 12),

                // Statut attente
                if (_room.status == CheckersRoomStatus.waiting)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: AppColors.neonOrange, strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          _room.guestId == null
                              ? 'En attente d\'un adversaire...'
                              : 'Lancement de la partie...',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                // ── Chat ──────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.divider.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        // Header chat
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.neonOrange
                                .withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(14)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  color: AppColors.neonOrange, size: 16),
                              SizedBox(width: 8),
                              Text('Chat',
                                  style: TextStyle(
                                      color: AppColors.neonOrange,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
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
                                        color: AppColors.textMuted
                                            .withValues(alpha: 0.4),
                                        fontSize: 13),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: EdgeInsets.all(10),
                                  itemCount: _messages.length,
                                  itemBuilder: (_, i) {
                                    final msg = _messages[i];
                                    final isMe =
                                        msg['user_id'] == myId;
                                    return _ChatBubble(
                                        msg: msg, isMe: isMe);
                                  },
                                ),
                        ),
                        // Input
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.bgCardLight
                                .withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(14)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Message...',
                                    hintStyle: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 14),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.send_rounded,
                                    color: AppColors.neonOrange, size: 20),
                                onPressed: _sendMessage,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                              ),
                            ],
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
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final String? username;
  final String pieceColor;
  final bool isReady;
  final String label;
  const _PlayerCard({this.username, required this.pieceColor, required this.isReady, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = pieceColor == 'red' ? Colors.red.shade400 : Colors.grey.shade400;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isReady ? AppColors.neonGreen.withValues(alpha: 0.4) : AppColors.divider),
      ),
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(Icons.circle, color: color, size: 22),
          ),
          SizedBox(height: 8),
          Text(
            username ?? (isReady ? 'Connecté' : 'En attente...'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: username != null ? AppColors.textPrimary : AppColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isReady
                  ? AppColors.neonGreen.withValues(alpha: 0.15)
                  : AppColors.textMuted.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isReady ? 'PRÊT' : 'ATTENTE',
              style: TextStyle(
                color: isReady ? AppColors.neonGreen : AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bulle de message chat ──────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;

  const _ChatBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final username = msg['username'] as String? ?? 'Joueur';
    final message = msg['message'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor:
                  AppColors.neonOrange.withValues(alpha: 0.2),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neonOrange),
              ),
            ),
            SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.neonOrange.withValues(alpha: 0.18)
                    : AppColors.bgCardLight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMe ? 12 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 12),
                ),
                border: Border.all(
                  color: isMe
                      ? AppColors.neonOrange.withValues(alpha: 0.3)
                      : AppColors.divider.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      username,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonOrange),
                    ),
                  Text(
                    message,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) SizedBox(width: 6),
        ],
      ),
    );
  }
}
