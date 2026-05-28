// ============================================================
// GameModel — modèle immutable d'un jeu du catalogue
// ============================================================
// Catalogue local Phase 1, prêt pour catalogue Supabase distant
// (fromJson/toJson). Modèle économique : Pay-to-play (entryPriceCoins
// débité au start_session, sessionDurationMinutes payée, AUCUN payout).
// ============================================================

import 'game_category.dart';

enum GameProvider { poki, internal, other }

class GameModel {
  final String id;
  final String slug;
  final String title;
  final String description;
  final GameCategory category;
  final GameProvider provider;
  final String embedUrl;
  final String? thumbnailUrl;
  final String? thumbnailAsset;
  final int entryPriceCoins;
  final int sessionDurationMinutes;
  final bool isEnabled;
  final bool featured;
  final List<String> tags;
  final String? minAppVersion;
  final String? injectionScript;

  const GameModel({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.provider,
    required this.embedUrl,
    required this.entryPriceCoins,
    required this.sessionDurationMinutes,
    this.thumbnailUrl,
    this.thumbnailAsset,
    this.isEnabled = true,
    this.featured = false,
    this.tags = const [],
    this.minAppVersion,
    this.injectionScript,
  });

  GameModel copyWith({
    String? title,
    String? description,
    GameCategory? category,
    String? embedUrl,
    String? thumbnailUrl,
    int? entryPriceCoins,
    int? sessionDurationMinutes,
    bool? isEnabled,
    bool? featured,
    String? injectionScript,
  }) {
    return GameModel(
      id: id,
      slug: slug,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      provider: provider,
      embedUrl: embedUrl ?? this.embedUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailAsset: thumbnailAsset,
      entryPriceCoins: entryPriceCoins ?? this.entryPriceCoins,
      sessionDurationMinutes:
          sessionDurationMinutes ?? this.sessionDurationMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      featured: featured ?? this.featured,
      tags: tags,
      minAppVersion: minAppVersion,
      injectionScript: injectionScript ?? this.injectionScript,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'description': description,
        'category': category.toJson(),
        'provider': provider.name,
        'embed_url': embedUrl,
        'thumbnail_url': thumbnailUrl,
        'thumbnail_asset': thumbnailAsset,
        'entry_price_coins': entryPriceCoins,
        'session_duration_minutes': sessionDurationMinutes,
        'is_enabled': isEnabled,
        'featured': featured,
        'tags': tags,
        'min_app_version': minAppVersion,
        'injection_script': injectionScript,
      };

  factory GameModel.fromJson(Map<String, dynamic> json) => GameModel(
        id: json['id'] as String,
        slug: json['slug'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        category: GameCategory.fromJson(json['category'] as String),
        provider: GameProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => GameProvider.other,
        ),
        embedUrl: json['embed_url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        thumbnailAsset: json['thumbnail_asset'] as String?,
        entryPriceCoins: (json['entry_price_coins'] as num).toInt(),
        sessionDurationMinutes:
            (json['session_duration_minutes'] as num).toInt(),
        isEnabled: (json['is_enabled'] as bool?) ?? true,
        featured: (json['featured'] as bool?) ?? false,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        minAppVersion: json['min_app_version'] as String?,
        injectionScript: json['injection_script'] as String?,
      );
}
