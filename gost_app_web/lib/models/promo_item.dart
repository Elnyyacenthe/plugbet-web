// ============================================================
// Plugbet – Modèle PromoItem
// ============================================================

class PromoItem {
  final String id;
  final String title;
  final String description;
  final String imageUrl; // Chemin d'un asset ou URL réseau
  final int winnersCount; // Nombre de gagnants (badge)
  final DateTime? endDate; // Date de fin pour le compte à rebours
  final String? destinationRoute; // Navigation optionnelle
  final String? actionLabel; // Texte du bouton CTA
  final bool isGrandPrix; // Si c'est la promotion vedette
  final String? highlightedReward; // Montant ou lot principal (ex: "1 000 000 FCFA")

  // ── Contenu de la page de détail (PromoDetailScreen), piloté par les données ──
  final String? longDescription; // Explication détaillée (fallback: description)
  final List<String> conditions; // Puces de conditions / éligibilité
  final String? badgeLabel; // Badge court (ex: "2UP", "NOUVEAU")

  const PromoItem({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.winnersCount,
    this.endDate,
    this.destinationRoute,
    this.actionLabel,
    this.isGrandPrix = false,
    this.highlightedReward,
    this.longDescription,
    this.conditions = const [],
    this.badgeLabel,
  });

  /// Affiche paysage de la promo, dérivée de [imageUrl] en insérant
  /// `_paysage` avant l'extension (ex: `2up.png` -> `2up_paysage.png`).
  /// Les affiches paysage couvrent les cartes (carousel, détail, liste).
  /// Repli sur [imageUrl] si réseau ou format inattendu.
  String get bannerImageUrl {
    if (imageUrl.isEmpty) return imageUrl;
    if (imageUrl.toLowerCase().startsWith('http')) return imageUrl;
    final dot = imageUrl.lastIndexOf('.');
    if (dot <= 0) return imageUrl;
    return '${imageUrl.substring(0, dot)}_paysage${imageUrl.substring(dot)}';
  }

  /// Permet d'indiquer si la promotion est toujours active
  bool get isActive {
    if (endDate == null) return true;
    return endDate!.isAfter(DateTime.now());
  }

  /// Retourne le temps restant sous forme de chaîne de caractères
  Duration get remainingTime {
    if (endDate == null) return Duration.zero;
    final diff = endDate!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
}
