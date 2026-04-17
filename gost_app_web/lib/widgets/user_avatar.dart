// ============================================================
// UserAvatar — Avatar partage pour le chat
// Affiche la photo de profil si disponible, sinon les initiales
// ============================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String username;
  final double size;
  final bool isOnline;
  final bool showOnlineDot;
  final double? onlineDotSize;
  final Color? ringColor;
  final double ringWidth;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.username,
    this.size = 46,
    this.isOnline = false,
    this.showOnlineDot = true,
    this.onlineDotSize,
    this.ringColor,
    this.ringWidth = 0,
    this.onTap,
  });

  String get _initials {
    if (username.isEmpty) return '?';
    return username[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = onlineDotSize ?? (size * 0.28).clamp(8.0, 16.0);
    final innerSize = ringWidth > 0 ? size - (ringWidth * 2) : size;

    Widget avatar = Container(
      width: innerSize,
      height: innerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonBlue.withValues(alpha: 0.35),
            AppColors.neonPurple.withValues(alpha: 0.35),
          ],
        ),
      ),
      child: ClipOval(
        child: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                width: innerSize,
                height: innerSize,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                memCacheWidth: (innerSize *
                        MediaQuery.of(context).devicePixelRatio)
                    .round(),
                placeholder: (_, __) => _initialsWidget(innerSize),
                errorWidget: (_, __, ___) => _initialsWidget(innerSize),
              )
            : _initialsWidget(innerSize),
      ),
    );

    // Ring externe (pour statuts)
    if (ringWidth > 0 && ringColor != null) {
      avatar = Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ringColor!,
              ringColor!.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgDark,
          ),
          child: avatar,
        ),
      );
    }

    Widget result = avatar;

    // Online dot
    if (showOnlineDot && isOnline) {
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: AppColors.neonGreen,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.bgDark,
                  width: dotSize * 0.18,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      result = GestureDetector(onTap: onTap, child: result);
    }

    return result;
  }

  Widget _initialsWidget(double s) {
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.neonBlue.withValues(alpha: 0.35),
            AppColors.neonPurple.withValues(alpha: 0.35),
          ],
        ),
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: s * 0.42,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
