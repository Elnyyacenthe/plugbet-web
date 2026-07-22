// ============================================================
// Checkers – Lobby (attente adversaire)
// ============================================================
import 'dart:async';
import 'dart:ui';
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

  /// Le host quitte avant qu'un guest n'ait joint -> refund + cancel.
  /// Idempotent cote serveur, donc safe a appeler plusieurs fois.
  Future<bool> _cancelIfHostWaiting() async {
    final uid = _service.currentUserId;
    if (uid == null || uid != _room.hostId) return false;
    if (_room.status != CheckersRoomStatus.waiting) return false;
    if (_room.guestId != null) return false;  // un guest a deja join
    return await _service.cancelWaitingRoom(_room.id);
  }

  Future<void> _handleBack() async {
    final cancelled = await _cancelIfHostWaiting();
    if (!mounted) return;
    if (cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partie annulee, mise remboursee')),
      );
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    // [A12] On NE déclenche PLUS l'annulation/refund de la room au
    // dispose : le dispose n'est pas un signal d'intention fiable
    // (recréation d'arbre sur changement thème/langue -> annulerait
    // une room en attente valide). L'annulation se fait uniquement
    // sur intention explicite (_handleBack confirmé). Les rooms
    // réellement abandonnées (kill app) sont nettoyées par le cron
    // serveur cleanup_stale_waiting. (Même raisonnement que Ludo F3.)
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    _service.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUserId;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Stack(
          children: [
            // Halos neon ambiants — purement decoratifs
            Positioned(
              top: -60,
              right: -40,
              child: _ambientBlob(AppColors.neonPurple, 180),
            ),
            Positioned(
              bottom: 40,
              left: -50,
              child: _ambientBlob(AppColors.neonOrange, 170),
            ),
            SafeArea(
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
                          onPressed: _handleBack,
                        ),
                        Expanded(
                          child: ShaderMask(
                            shaderCallback: (r) => LinearGradient(colors: [
                              AppColors.textPrimary,
                              AppColors.neonOrange.withValues(alpha: 0.85),
                            ]).createShader(r),
                            child: Text('Lobby – Dames',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          margin: EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.neonPurple.withValues(alpha: 0.22),
                                AppColors.neonPurple.withValues(alpha: 0.06),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.neonPurple
                                    .withValues(alpha: 0.5),
                                width: 1),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.neonPurple.withValues(alpha: 0.3),
                                blurRadius: 16,
                              ),
                            ],
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
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: 4)),
                              SizedBox(width: 8),
                              Icon(Icons.copy,
                                  color: AppColors.neonPurple, size: 14),
                            ],
                          ),
                        ),
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
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.neonYellow.withValues(alpha: 0.20),
                        AppColors.neonYellow.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.45)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonYellow.withValues(alpha: 0.22),
                        blurRadius: 14,
                      ),
                    ],
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
                              fontWeight: FontWeight.w800,
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
            ],
          ),
      ),
      ),
    );
  }

  /// Tache de lumiere floue purement decorative (glassmorphism ambiant).
  Widget _ambientBlob(Color color, double size) {
    return IgnorePointer(
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgCardLight, AppColors.bgCard],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isReady
                ? AppColors.neonGreen.withValues(alpha: 0.5)
                : AppColors.divider),
        boxShadow: isReady
            ? [
                BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.22),
                    blurRadius: 12),
              ]
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4)),
              ],
      ),
      child: Column(
        children: [
          // Jeton de dames 3D (dôme + rainure + reflet spéculaire)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                colors: [
                  Color.lerp(color, Colors.white, 0.55)!,
                  color,
                  Color.lerp(color, Colors.black, 0.4)!,
                ],
                stops: const [0, 0.55, 1],
              ),
              border:
                  Border.all(color: Colors.black.withValues(alpha: 0.25), width: 1.5),
              boxShadow: [
                const BoxShadow(
                    color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                if (isReady)
                  BoxShadow(
                      color: AppColors.neonGreen.withValues(alpha: 0.4),
                      blurRadius: 10),
              ],
            ),
            child: Stack(
              children: [
                // Rainure fraisée
                Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.black.withValues(alpha: 0.28),
                          width: 1.4),
                    ),
                  ),
                ),
                // Reflet spéculaire
                Align(
                  alignment: const Alignment(-0.4, -0.45),
                  child: FractionallySizedBox(
                    widthFactor: 0.26,
                    heightFactor: 0.26,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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