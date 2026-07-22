// ============================================================
// MarketLabels — Traduction codes marche -> labels humains
// ============================================================
// Centralise TOUS les libelles de paris (soccer + basket) pour qu'aucune
// section UI n'ait de "Total de buts" sur un match NBA, ou "Total de
// points" sur un soccer. La couche conversion est sport-aware et
// extensible (ajouter d'autres sports = ajouter switch case).
//
// Utilisateurs :
// - BettingScreen._buildSelection : compose marketLabel pour BetSlip
// - BettingMatchDetailScreen : section titles + tile labels + bet labels
// - VirtualMatchesScreen : marketLabel virtuels (toujours soccer)
// - BetsHistoryScreen : affiche marketLabel tel quel (deja formate)
// ============================================================

import '../services/statpal_service.dart' show Sport;

class MarketLabels {
  MarketLabels._();

  static bool _usesGoals(Sport sport) =>
      sport == Sport.soccer ||
      sport == Sport.iceHockey ||
      sport == Sport.handball;

  static String _totalUnit(Sport sport) {
    switch (sport) {
      case Sport.soccer:
      case Sport.iceHockey:
      case Sport.handball:
        return 'buts';
      case Sport.basketball:
      case Sport.americanFootball:
      case Sport.rugby:
        return 'points';
      case Sport.baseball:
        return 'runs';
      case Sport.tennis:
        return 'jeux';
    }
  }

  static String _totalTitle(Sport sport, double? line) {
    final unit = _totalUnit(sport);
    if (_usesGoals(sport)) return 'Total de buts +/- ${_fmt(line ?? 2.5)}';
    return line != null ? 'Total de $unit (${_fmt(line)})' : 'Total de $unit';
  }

  /// Decode "ah_home@-1.5" -> ("ah_home", -1.5). Renvoie (code, null) si pas d'arobase.
  /// Utilise pour Asian Handicap dont la ligne est encodee dans le code.
  static ({String base, double? line}) parseLine(String code) {
    final at = code.indexOf('@');
    if (at < 0) return (base: code, line: null);
    final base = code.substring(0, at);
    final line = double.tryParse(code.substring(at + 1));
    return (base: base, line: line);
  }

  /// Formate une ligne signee : -1.5 -> "-1,5"  | +0.5 -> "+0,5"  | 0 -> "0"
  static String _fmtSigned(double v) {
    if (v == 0) return '0';
    final s = _fmt(v.abs());
    return v > 0 ? '+$s' : '-$s';
  }

  /// Titre de section de marche dans l'ecran detail.
  /// Ex: 'home' soccer -> '1X2'  |  'home' basket -> 'Moneyline'
  /// Avec [line] : "Total de points (107.5)" / "Total de buts +/- 2,5"
  static String sectionTitle(String code, Sport sport, {double? line}) {
    // Asian Handicap (soccer) — code "ah_home@-1.5" ou "ah_home" + line param
    if (code.startsWith('ah_')) {
      final parsed = parseLine(code);
      final l = parsed.line ?? line;
      return l != null
          ? 'Handicap asiatique (${_fmtSigned(l)})'
          : 'Handicap asiatique';
    }
    // Mi-temps soccer
    if (code.startsWith('ht_') &&
        (code.endsWith('_home') ||
            code == 'ht_draw' ||
            code.endsWith('_away'))) {
      return '1X2 mi-temps';
    }
    if (code == 'ht_over15' || code == 'ht_under15') {
      return 'Buts mi-temps +/- 1,5';
    }
    // 1X2 / Moneyline
    if (code == 'home' || code == 'draw' || code == 'away') {
      return _usesGoals(sport) ? '1X2' : 'Moneyline';
    }
    // Double Chance (soccer only)
    if (code.startsWith('dc_')) return 'Double chance';
    // OU
    if (code == 'over25' || code == 'under25') {
      return _totalTitle(sport, line);
    }
    // Spread / Handicap (basket principalement)
    if (code == 'spread_home' || code == 'spread_away') {
      return 'Handicap';
    }
    // BTTS (soccer only)
    if (code == 'btts_yes' || code == 'btts_no') {
      return 'Les deux équipes marquent';
    }
    return code;
  }

  /// Formate une ligne (ex: 107.5, 2.5) sans .0 inutiles
  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Sous-titre descriptif sous le titre de section.
  static String sectionSubtitle(String code, Sport sport) {
    if (code.startsWith('ah_')) {
      return 'Handicap virtuel appliqué au score final';
    }
    if (code.startsWith('ht_') &&
        (code.endsWith('_home') ||
            code == 'ht_draw' ||
            code.endsWith('_away'))) {
      return 'Résultat à la fin de la 1ère mi-temps';
    }
    if (code == 'ht_over15' || code == 'ht_under15') {
      return 'Buts marqués pendant la 1ère mi-temps';
    }
    if (code == 'home' || code == 'draw' || code == 'away') {
      return _usesGoals(sport)
          ? 'Résultat à la fin du temps réglementaire'
          : 'Vainqueur du match';
    }
    if (code.startsWith('dc_')) {
      return '2 résultats couverts sur 3 (cote calculée)';
    }
    if (code == 'over25' || code == 'under25') {
      final unit = _totalUnit(sport);
      return _usesGoals(sport)
          ? 'Total de buts dans le match'
          : 'Total de $unit dans le match (ligne main bookmaker)';
    }
    if (code == 'btts_yes' || code == 'btts_no') {
      return 'Score chacune au moins 1 but';
    }
    return '';
  }

  /// Texte court affiche sur le bouton de cote.
  /// Ex: 'home' -> '1'  |  'over25' basket -> 'Plus 107.5'  |  'over25' soccer -> '+2.5'
  static String tileShort(String code, Sport sport, {double? line}) {
    // Asian Handicap : "ah_home@-1.5" -> "1 (-1,5)"
    if (code.startsWith('ah_')) {
      final parsed = parseLine(code);
      final l = parsed.line ?? line;
      final side = parsed.base == 'ah_home' ? '1' : '2';
      // Cote home : ligne telle quelle. Cote away : ligne inversee
      // (StatPal donne le meme `name` (-1.5) pour les 2 cotes, l'inversion
      // se fait cote affichage uniquement).
      final shown = parsed.base == 'ah_away' && l != null ? -l : l;
      return shown != null ? '$side (${_fmtSigned(shown)})' : side;
    }
    switch (code) {
      case 'home':
        return '1';
      case 'draw':
        return 'X';
      case 'away':
        return '2';
      case 'dc_1x':
        return '1X';
      case 'dc_12':
        return '12';
      case 'dc_x2':
        return 'X2';
      case 'over25':
        return _usesGoals(sport)
            ? '+${_fmt(line ?? 2.5)}'
            : (line != null ? 'Plus ${_fmt(line)}' : 'Plus');
      case 'under25':
        return _usesGoals(sport)
            ? '-${_fmt(line ?? 2.5)}'
            : (line != null ? 'Moins ${_fmt(line)}' : 'Moins');
      case 'spread_home':
        return line != null
            ? (line > 0 ? '+${_fmt(line)}' : _fmt(line))
            : 'Home';
      case 'spread_away':
        return line != null
            ? (line > 0 ? '+${_fmt(line)}' : _fmt(line))
            : 'Away';
      case 'btts_yes':
        return 'Oui';
      case 'btts_no':
        return 'Non';
      case 'ht_home':
        return '1 MT';
      case 'ht_draw':
        return 'X MT';
      case 'ht_away':
        return '2 MT';
      case 'ht_over15':
        return '+1.5 MT';
      case 'ht_under15':
        return '-1.5 MT';
      default:
        return code;
    }
  }

  /// Description longue sous le bouton (sous le label court).
  /// Ex: 'home' -> 'Real Madrid'  |  'over25' basket -> 'Plus de points'
  static String tileLong(String code, Sport sport,
      {String? homeName, String? awayName, double? line}) {
    final h = homeName ?? 'Domicile';
    final a = awayName ?? 'Extérieur';
    // Asian Handicap : "Atletico-MG (-1,5)"
    if (code.startsWith('ah_')) {
      final parsed = parseLine(code);
      final l = parsed.line ?? line;
      final team = parsed.base == 'ah_home' ? h : a;
      final shown = parsed.base == 'ah_away' && l != null ? -l : l;
      return shown != null ? '$team (${_fmtSigned(shown)})' : team;
    }
    switch (code) {
      case 'home':
        return h;
      case 'draw':
        return 'Match nul';
      case 'away':
        return a;
      case 'dc_1x':
        return '$h ou nul';
      case 'dc_12':
        return 'Pas de nul';
      case 'dc_x2':
        return '$a ou nul';
      case 'over25':
        final unitName = _totalUnit(sport);
        return line != null
            ? 'Plus de ${_fmt(line)} $unitName'
            : 'Plus de $unitName';
      case 'under25':
        final unitName = _totalUnit(sport);
        return line != null
            ? 'Moins de ${_fmt(line)} $unitName'
            : 'Moins de $unitName';
      case 'spread_home':
        return line != null
            ? '$h ${line > 0 ? '+' : ''}${_fmt(line)}'
            : '$h handicap';
      case 'spread_away':
        return line != null
            ? '$a ${line > 0 ? '+' : ''}${_fmt(line)}'
            : '$a handicap';
      case 'btts_yes':
        return 'Les deux marquent';
      case 'btts_no':
        return 'Au moins une n\'a pas marqué';
      case 'ht_home':
        return '$h (MT)';
      case 'ht_draw':
        return 'Match nul (MT)';
      case 'ht_away':
        return '$a (MT)';
      case 'ht_over15':
        return 'Plus de 1,5 buts MT';
      case 'ht_under15':
        return 'Moins de 1,5 buts MT';
      default:
        return code;
    }
  }

  /// Label complet stocke dans BetSelection.marketLabel (visible panier + historique).
  /// Format : "{section} — {tileLong}"
  /// Ex: 'home' soccer Real-Madrid -> "1X2 — Real Madrid"
  ///     'over25' basket 107.5     -> "Total de points (107.5) — Plus de 107.5 points"
  static String selectionLabel(String code, Sport sport,
      {String? homeName, String? awayName, double? line}) {
    final section = sectionTitle(code, sport, line: line);
    final tile = tileLong(code, sport,
        homeName: homeName, awayName: awayName, line: line);
    return '$section — $tile';
  }
}
