// ============================================================
// BetTeamCrest — Avatar circulaire par equipe (paris)
// ============================================================
// Affiche, par ordre de priorite :
// 1. logoUrl explicite si passe en parametre
// 2. Logo via TheSportsDB (charge en background au 1er affichage)
// 3. Fallback : avatar coule + initiales generes depuis le nom
//
// Le lookup TheSportsDB est asynchrone mais non-bloquant :
// les initiales s'affichent tout de suite, le vrai logo arrive
// quand fetch termine (zero flicker grace au cache memoire).
// ============================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/statpal_service.dart' show Sport;
import '../services/team_logo_service.dart';

class BetTeamCrest extends StatefulWidget {
  final String name;
  final String? logoUrl;       // URL explicite (StatPal si dispo, sinon null)
  final Sport sport;            // pour filtrer TheSportsDB
  final double size;

  const BetTeamCrest({
    super.key,
    required this.name,
    this.logoUrl,
    this.sport = Sport.soccer,
    this.size = 32,
  });

  @override
  State<BetTeamCrest> createState() => _BetTeamCrestState();
}

class _BetTeamCrestState extends State<BetTeamCrest> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
    _maybeFetch();
    TeamLogoService.instance.addListener(_onLogoUpdate);
  }

  @override
  void didUpdateWidget(BetTeamCrest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.sport != widget.sport) {
      _resolveUrl();
      _maybeFetch();
    }
  }

  @override
  void dispose() {
    TeamLogoService.instance.removeListener(_onLogoUpdate);
    super.dispose();
  }

  /// Listener service : ne rebuild QUE si l'URL pour CETTE equipe a change.
  /// Avant : tout BetTeamCrest rebuildait sur chaque notify global -> cascade
  /// de re-decodes Image.network -> flicker visible. Maintenant : zero rebuild
  /// si l'URL stable pour mon equipe.
  void _onLogoUpdate() {
    if (!mounted) return;
    final newUrl = _computeUrl();
    if (newUrl != _resolvedUrl) {
      setState(() => _resolvedUrl = newUrl);
    }
  }

  void _resolveUrl() {
    _resolvedUrl = _computeUrl();
  }

  String? _computeUrl() {
    if (widget.logoUrl?.isNotEmpty == true) return widget.logoUrl;
    return TeamLogoService.instance.getCached(widget.name, widget.sport);
  }

  void _maybeFetch() {
    if (widget.logoUrl != null && widget.logoUrl!.isNotEmpty) return;
    TeamLogoService.instance.prefetch(widget.name, widget.sport);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(widget.name);
    final color = _colorFromName(widget.name);

    final placeholder = Container(
      width: widget.size, height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.62)],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 4, offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * 0.38,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          )),
    );

    final resolvedUrl = _resolvedUrl;
    if (resolvedUrl == null || resolvedUrl.isEmpty) return placeholder;

    // CachedNetworkImage : cache disque + memoire persistant, decode
    // une seule fois et reaffiche instantanement les builds suivants.
    // Elimine le flicker des Image.network qui re-decodait a chaque rebuild.
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        // Cle stable pour ne pas re-keyer entre builds
        cacheKey: resolvedUrl,
        // Pendant le 1er fetch : placeholder. Apres : instantane (cache).
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
        // Fade discret pour transition fluide
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
      ),
    );
  }

  /// "Real Madrid" -> "RM" ; "Paris SG" -> "PS" ; "Al Ahly" -> "AA"
  String _initials(String raw) {
    var cleaned = raw.trim();
    const prefixes = ['FC ', 'AC ', 'AS ', 'AFC ', 'CF ', 'SC ', 'CD '];
    for (final p in prefixes) {
      if (cleaned.toUpperCase().startsWith(p)) {
        cleaned = cleaned.substring(p.length);
        break;
      }
    }
    final words =
        cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words[0];
      return w.length >= 2
          ? w.substring(0, 2).toUpperCase()
          : w.substring(0, 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  Color _colorFromName(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = ((h * 31) + c) & 0x7FFFFFFF;
    }
    const palette = <Color>[
      Color(0xFF1976D2), Color(0xFFD32F2F), Color(0xFF7B1FA2),
      Color(0xFF388E3C), Color(0xFFF57C00), Color(0xFF00796B),
      Color(0xFFC2185B), Color(0xFF512DA8), Color(0xFF455A64),
      Color(0xFFE64A19), Color(0xFF5D4037), Color(0xFF0288D1),
      Color(0xFFAFB42B), Color(0xFFFBC02D),
    ];
    return palette[h % palette.length];
  }
}
