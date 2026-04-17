// ============================================================
// MessageBubble — Bulle de message WhatsApp-like
// Gere : texte, image, voice, reply, edited, deleted, reactions, isRead
// ============================================================
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final PrivateMessage message;
  final bool isMe;
  final List<PrivateMessage> allMessages;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.allMessages,
  });

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: message.reactions.isEmpty ? 4 : 14),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) const SizedBox(width: 50),
          Flexible(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.neonGreen.withValues(alpha: 0.15)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: Border.all(
                      color: isMe
                          ? AppColors.neonGreen.withValues(alpha: 0.2)
                          : AppColors.divider.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToId != null) _buildReplyPreview(),
                      _buildContent(context),
                      const SizedBox(height: 3),
                      _buildFooter(),
                    ],
                  ),
                ),
                if (message.reactions.isNotEmpty) _buildReactionsOverlay(),
              ],
            ),
          ),
          if (!isMe) const SizedBox(width: 50),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context)!.chatMessageDeleted,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    if (message.messageType == MessageType.image && message.mediaUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          message.mediaUrl!,
          width: 220,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 220,
              height: 150,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonGreen,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 220,
            height: 100,
            color: AppColors.bgCard,
            child: Icon(Icons.broken_image, color: AppColors.textMuted),
          ),
        ),
      );
    }

    if (message.messageType == MessageType.voice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 18, color: AppColors.neonGreen),
          const SizedBox(width: 6),
          Text(
            '${message.mediaDuration ?? 0}s',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            width: 120,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    }

    return Text(
      message.content,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited)
          Text(
            'modifie ',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
          ),
        Text(
          _formatTime(message.createdAt),
          style: TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
        if (isMe && !message.isDeleted) ...[
          const SizedBox(width: 3),
          Icon(
            message.isRead ? Icons.done_all : Icons.done,
            size: 13,
            color: message.isRead
                ? AppColors.neonGreen
                : AppColors.textMuted,
          ),
        ],
      ],
    );
  }

  Widget _buildReplyPreview() {
    final original =
        allMessages.where((m) => m.id == message.replyToId).firstOrNull;
    final previewText = original?.content ?? '...';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.bgDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppColors.neonGreen, width: 3),
        ),
      ),
      child: Text(
        previewText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _buildReactionsOverlay() {
    final grouped = <String, int>{};
    for (final r in message.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }
    final chips = grouped.entries
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '${e.key}${e.value > 1 ? e.value : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        )
        .toList();

    return Positioned(
      bottom: -10,
      right: isMe ? null : 8,
      left: isMe ? 8 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: chips),
      ),
    );
  }
}
