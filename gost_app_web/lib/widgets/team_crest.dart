// ============================================================
// Plugbet – Widget du blason d'équipe
// Supporte SVG + PNG avec gestion d'erreur propre
// ============================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';

class TeamCrest extends StatelessWidget {
  final Team team;
  final double size;

  const TeamCrest({
    super.key,
    required this.team,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final url = team.crestUrl;

    if (url == null || url.isEmpty) {
      return _initialsWidget();
    }

    // --- SVG ---
    if (url.toLowerCase().endsWith('.svg')) {
      return _SvgCrest(url: url, size: size, fallback: _initialsWidget());
    }

    // --- PNG / JPG ---
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, __) => _initialsWidget(),
      errorWidget: (_, __, ___) => _initialsWidget(),
    );
  }

  Widget _initialsWidget() {
    final initials = team.tla ??
        team.shortName.substring(0, team.shortName.length.clamp(0, 3));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgCardLight, AppColors.bgCard],
        ),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.3,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

/// Widget SVG avec gestion d'erreur intégrée (évite les exceptions non catchées)
class _SvgCrest extends StatefulWidget {
  final String url;
  final double size;
  final Widget fallback;

  const _SvgCrest({
    required this.url,
    required this.size,
    required this.fallback,
  });

  @override
  State<_SvgCrest> createState() => _SvgCrestState();
}

class _SvgCrestState extends State<_SvgCrest> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback;
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: SvgPicture.network(
        widget.url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => widget.fallback,
        errorBuilder: (_, __, ___) {
          // Marquer comme erreur pour ne pas retenter
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _hasError = true);
          });
          return widget.fallback;
        },
      ),
    );
  }
}
