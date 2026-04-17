// ============================================================
// StatusViewerScreen — Visualisation plein ecran des statuts
// Style WhatsApp : auto-advance 5s, tap pour pause, swipe pour navigation
// ============================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../services/messaging_service.dart';
import '../widgets/user_avatar.dart';

class StatusViewerScreen extends StatefulWidget {
  final List<UserStatusGroup> groups;
  final int initialGroupIndex;

  const StatusViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _statusDuration = Duration(seconds: 5);

  final _messagingService = MessagingService();
  late AnimationController _progressController;
  late int _groupIndex;
  int _statusIndex = 0;
  bool _paused = false;

  UserStatusGroup get _currentGroup => widget.groups[_groupIndex];
  UserStatus get _currentStatus => _currentGroup.statuses[_statusIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _progressController = AnimationController(
      vsync: this,
      duration: _statusDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _startStatus();
  }

  void _startStatus() {
    _progressController.reset();
    _progressController.forward();
    _messagingService.markStatusViewed(_currentStatus.id);
  }

  void _next() {
    if (_statusIndex < _currentGroup.statuses.length - 1) {
      setState(() => _statusIndex++);
      _startStatus();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _statusIndex = 0;
      });
      _startStatus();
    } else {
      Navigator.pop(context);
    }
  }

  void _previous() {
    if (_statusIndex > 0) {
      setState(() => _statusIndex--);
      _startStatus();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _statusIndex = _currentGroup.statuses.length - 1;
      });
      _startStatus();
    }
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progressController.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _currentStatus;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < screenWidth * 0.3) {
              _previous();
            } else {
              _next();
            }
          },
          onLongPressStart: (_) => _pause(),
          onLongPressEnd: (_) => _resume(),
          child: Stack(
            children: [
              // Media plein ecran
              Positioned.fill(
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: status.mediaUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 60,
                    ),
                  ),
                ),
              ),

              // Degrade haut pour lisibilite
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 110,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xCC000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Barres de progression
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: List.generate(_currentGroup.statuses.length, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: EdgeInsets.symmetric(
                            horizontal: i == 0 ? 0 : 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: i < _statusIndex
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              )
                            : i == _statusIndex
                                ? AnimatedBuilder(
                                    animation: _progressController,
                                    builder: (_, __) => FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _progressController.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                      ),
                    );
                  }),
                ),
              ),

              // Header utilisateur
              Positioned(
                top: 28,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    UserAvatar(
                      avatarUrl: _currentGroup.avatarUrl,
                      username: _currentGroup.username,
                      size: 40,
                      showOnlineDot: false,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentGroup.username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            _formatTime(status.createdAt),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Caption en bas
              if (status.caption != null && status.caption!.isNotEmpty)
                Positioned(
                  bottom: 32,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'a l\'instant';
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return 'hier';
  }
}
