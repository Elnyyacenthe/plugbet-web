// ============================================================
// Currency - Label et formatage devise selon le pays
// ============================================================
// Le champ DB reste 'FCFA' (pas de migration), seul l'AFFICHAGE change.
//
// Couvre :
//   • Zone CEMAC (XAF) : CM, CF, TD, CG, GA, GQ -> FCFA
//   • Zone UEMOA (XOF) : SN, CI, BF, ML, NE, BJ, TG, GW -> FCFA
//   • Zone euro : FR, BE, DE, IT, ES, etc. -> EUR
//   • USA / UK -> USD / GBP
//   • Par defaut : FCFA (marche principal Cameroun)
// ============================================================

import 'dart:ui';
import 'package:flutter/widgets.dart';

class Currency {
  /// Label principal (ex: "FCFA", "EUR", "USD").
  /// Si [context] fourni, utilise la locale de l'app ; sinon la locale systeme.
  static String label([BuildContext? context]) {
    final cc = _countryCode(context);
    switch (cc) {
      // CEMAC (XAF)
      case 'CM':
      case 'CF':
      case 'TD':
      case 'CG':
      case 'GA':
      case 'GQ':
      // UEMOA (XOF) - meme label affiche
      case 'SN':
      case 'CI':
      case 'BF':
      case 'ML':
      case 'NE':
      case 'BJ':
      case 'TG':
      case 'GW':
        return 'FCFA';
      case 'FR':
      case 'BE':
      case 'DE':
      case 'IT':
      case 'ES':
      case 'NL':
      case 'PT':
      case 'AT':
      case 'IE':
      case 'FI':
      case 'GR':
        return 'EUR';
      case 'US':
        return 'USD';
      case 'GB':
        return 'GBP';
      case 'CA':
        return 'CAD';
      case 'CH':
        return 'CHF';
      case 'MA':
        return 'MAD';
      case 'DZ':
        return 'DZD';
      case 'TN':
        return 'TND';
      case 'NG':
        return 'NGN';
      default:
        return 'FCFA'; // Marche principal
    }
  }

  /// Formate un montant : "1 000 FCFA"
  static String format(num amount, [BuildContext? context]) {
    final digits = amount.toInt().toString();
    final withSpaces = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
    return '$withSpaces ${label(context)}';
  }

  static String _countryCode(BuildContext? context) {
    if (context != null) {
      final locale = Localizations.maybeLocaleOf(context);
      if (locale?.countryCode != null && locale!.countryCode!.isNotEmpty) {
        return locale.countryCode!.toUpperCase();
      }
    }
    final sys = PlatformDispatcher.instance.locale;
    return sys.countryCode?.toUpperCase() ?? 'CM';
  }
}
