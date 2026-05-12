// ============================================================
// CORA DICE - Lobby (Salle d'attente)
// Affiche joueurs, ready check, chat, démarre partie
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
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
  bool _isLoading = true;

  RealtimeChannel? _roomChannel;
  RealtimeChannel? _playersChannel;
  RealtimeChannel? _messagesChannel;

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // Countdown timer pour l'auto-start (V3.2 : 2 min)
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadRoom();
    _loadPlayers();
    _loadMessages();
    _subscribeToUpdates();
    _startCountdownTicker();
  }

  void _startCountdownTicker() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final dl = _room?.startDeadline;
      if (dl == null) {
        setState(() => _remaining = Duration.zero);
        return;
      }
      final r = dl.difference(DateTime.now());
      setState(() => _remaining = r.isNegative ? Duration.zero : r);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    if (_roomChannel != null) _service.unsubscribe(_roomChannel!);
    if (_playersChannel != null) _service.unsubscribe(_playersChannel!);
    if (_messagesChannel != null) _service.unsubscribe(_messagesChannel!);
    super.dispose();
  }

  String? _loadError;

  Future<void> _loadRoom() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final room = await _service.getRoom(widget.roomId);
      if (!mounted) return;
      if (room == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Salle introuvable. Elle a peut-être été annulée.';
        });
        return;
      }

      // Filet de sécurité : si la room est DÉJÀ en 'playing' au moment où
      // on ouvre le lobby (ex. join a déclenché _cora_start_game avant que
      // l'écran soit prêt), on saute le lobby et on file directement vers
      // l'écran de jeu. Sinon le user resterait bloqué en spinner.
      if (room.status == CoraRoomStatus.playing && room.gameId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CoraGameScreen(gameId: room.gameId!),
          ),
        );
        return;
      }

      setState(() {
        _room = room;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Erreur de chargement : $e';
      });
    }
  }

  Future<void> _loadPlayers() async {
    try {
      final data = await Supabase.instance.client
          .from('cora_room_players')
          .select()
          .eq('room_id', widget.roomId)
          .order('joined_at');
      setState(() => _players = List<Map<String, dynamic>>.from(data));
      // V3.3 : système Ready supprimé — tous les joueurs sont auto-ready au join.
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
      if (!mounted) return;
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
      // Si la room a été annulée (deadline auto-cancel ou host_left),
      // on remonte avec un message clair + refresh du wallet pour que
      // l'utilisateur voie son refund tout de suite.
      else if (room.status == CoraRoomStatus.cancelled) {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Room annulée — pas assez de joueurs prêts. Mise refundée.',
            ),
            backgroundColor: AppColors.neonRed,
            duration: const Duration(seconds: 3),
          ),
        );
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.pop(context);
        });
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen),
        ),
      );
    }
    if (_room == null) {
      // État d'erreur explicite : on évite le spinner infini.
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: AppColors.neonRed, size: 64),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'Impossible de charger la salle',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Retour',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loadRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonGreen,
                        foregroundColor: AppColors.bgDark,
                      ),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
            Text(AppLocalizations.of(context)!.gameWaitingRoom, style: TextStyle(fontSize: 16)),
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
                  content: Text(AppLocalizations.of(context)!.gameCodeCopied),
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
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds % 60;
    final hasDeadline = _room!.startDeadline != null;
    final timedOut = hasDeadline && _remaining == Duration.zero;
    final isFull = _players.length >= _room!.playerCount;
    final timerColor = _remaining.inSeconds < 30
        ? AppColors.neonRed
        : (_remaining.inSeconds < 60 ? AppColors.neonYellow : AppColors.neonGreen);

    return Column(
      children: [
        Container(
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
        ),
        if (hasDeadline)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: timerColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: timerColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  isFull ? Icons.play_circle_outline : Icons.timer_outlined,
                  color: timerColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isFull
                        ? 'Salle complète — démarrage en cours…'
                        : timedOut
                            ? 'Délai écoulé — salle non remplie.\nRoom annulée, mise refundée.'
                            : 'Démarrage auto dans ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}\n'
                              'En attente de joueurs (${_players.length}/${_room!.playerCount})',
                    style: TextStyle(
                      color: timerColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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
              // Avatar (toujours vert : tout le monde est ready par défaut)
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.neonGreen,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.bgDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isMe ? AppColors.neonGreen : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isMe) ...[
                const SizedBox(height: 2),
                Text(
                  '(toi)',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
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

  // V3.3 : plus de bouton Prêt — bouton "Quitter la salle"
  Widget _buildReadyButton() {
    final isFull = _players.length >= _room!.playerCount;
    return Container(
      padding: EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: isFull ? null : _confirmExit,
          style: ElevatedButton.styleFrom(
            backgroundColor: isFull ? AppColors.bgElevated : AppColors.neonRed,
            foregroundColor: isFull ? AppColors.textMuted : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            isFull ? 'Démarrage…' : 'Quitter la salle',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
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

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.gameLeaveRoomQuestion,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Voulez-vous vraiment quitter cette salle?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // V3 : cora_leave_room refund la mise du joueur via le ledger
              // si la room est encore en attente. Idempotent côté serveur.
              try {
                await _service.leaveRoom(widget.roomId);
              } catch (_) {}
              if (mounted) Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.gameQuit,
                style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}
