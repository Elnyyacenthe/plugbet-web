// ============================================================
// Plugbet – Liste de pays + drapeau + devise
// ============================================================
// Utilisé par la page d'inscription (sélecteur « Votre pays » et champ
// « Devise » dérivé du pays). Le drapeau emoji est calculé à partir du
// code ISO ; la devise suit les zones CEMAC/UEMOA/EUR/etc.
// ============================================================

import 'dart:ui';

class Country {
  final String code; // ISO 3166-1 alpha-2 (ex: 'CM')
  final String name; // Nom affiché (FR)
  final String dial; // Indicatif téléphonique sans '+' (ex: '237')

  const Country(this.code, this.name, this.dial);

  /// Drapeau emoji dérivé du code (regional indicator symbols).
  String get flag {
    if (code.length != 2) return '🏳️';
    const base = 0x1F1E6; // 'A' regional indicator
    final a = base + (code.codeUnitAt(0) - 0x41);
    final b = base + (code.codeUnitAt(1) - 0x41);
    return String.fromCharCode(a) + String.fromCharCode(b);
  }
}

/// Infos de devise affichées dans le champ non modifiable.
class CurrencyInfo {
  final String iso; // Code ISO (ex: 'XAF')
  final String label; // Label court (ex: 'FCFA')
  final String name; // Nom long (ex: 'Franc CFA')
  const CurrencyInfo(this.iso, this.label, this.name);
}

/// Liste des pays proposés (Afrique francophone en tête + international).
const List<Country> kCountries = [
  Country('CM', 'Cameroun', '237'),
  Country('CI', "Côte d'Ivoire", '225'),
  Country('SN', 'Sénégal', '221'),
  Country('GA', 'Gabon', '241'),
  Country('CG', 'Congo', '242'),
  Country('CD', 'RD Congo', '243'),
  Country('TD', 'Tchad', '235'),
  Country('CF', 'Centrafrique', '236'),
  Country('GQ', 'Guinée équatoriale', '240'),
  Country('BF', 'Burkina Faso', '226'),
  Country('ML', 'Mali', '223'),
  Country('NE', 'Niger', '227'),
  Country('BJ', 'Bénin', '229'),
  Country('TG', 'Togo', '228'),
  Country('GW', 'Guinée-Bissau', '245'),
  Country('GN', 'Guinée', '224'),
  Country('NG', 'Nigeria', '234'),
  Country('GH', 'Ghana', '233'),
  Country('KE', 'Kenya', '254'),
  Country('ZA', 'Afrique du Sud', '27'),
  Country('MA', 'Maroc', '212'),
  Country('DZ', 'Algérie', '213'),
  Country('TN', 'Tunisie', '216'),
  Country('FR', 'France', '33'),
  Country('BE', 'Belgique', '32'),
  Country('CH', 'Suisse', '41'),
  Country('DE', 'Allemagne', '49'),
  Country('IT', 'Italie', '39'),
  Country('ES', 'Espagne', '34'),
  Country('PT', 'Portugal', '351'),
  Country('NL', 'Pays-Bas', '31'),
  Country('GB', 'Royaume-Uni', '44'),
  Country('US', 'États-Unis', '1'),
  Country('CA', 'Canada', '1'),
];

const _cemac = {'CM', 'CF', 'TD', 'CG', 'GA', 'GQ'};
const _uemoa = {'SN', 'CI', 'BF', 'ML', 'NE', 'BJ', 'TG', 'GW'};
const _euro = {
  'FR', 'BE', 'DE', 'IT', 'ES', 'NL', 'PT', 'AT', 'IE', 'FI', 'GR'
};

/// Devise associée à un pays.
CurrencyInfo currencyForCountry(String code) {
  final cc = code.toUpperCase();
  if (_cemac.contains(cc)) return const CurrencyInfo('XAF', 'FCFA', 'Franc CFA');
  if (_uemoa.contains(cc)) return const CurrencyInfo('XOF', 'FCFA', 'Franc CFA');
  if (_euro.contains(cc)) return const CurrencyInfo('EUR', 'EUR', 'Euro');
  switch (cc) {
    case 'US':
      return const CurrencyInfo('USD', 'USD', 'Dollar US');
    case 'GB':
      return const CurrencyInfo('GBP', 'GBP', 'Livre sterling');
    case 'CA':
      return const CurrencyInfo('CAD', 'CAD', 'Dollar canadien');
    case 'CH':
      return const CurrencyInfo('CHF', 'CHF', 'Franc suisse');
    case 'MA':
      return const CurrencyInfo('MAD', 'MAD', 'Dirham');
    case 'DZ':
      return const CurrencyInfo('DZD', 'DZD', 'Dinar algérien');
    case 'TN':
      return const CurrencyInfo('TND', 'TND', 'Dinar tunisien');
    case 'NG':
      return const CurrencyInfo('NGN', 'NGN', 'Naira');
    case 'GH':
      return const CurrencyInfo('GHS', 'GHS', 'Cedi');
    case 'KE':
      return const CurrencyInfo('KES', 'KES', 'Shilling');
    case 'CD':
      return const CurrencyInfo('CDF', 'CDF', 'Franc congolais');
    case 'GN':
      return const CurrencyInfo('GNF', 'GNF', 'Franc guinéen');
    case 'ZA':
      return const CurrencyInfo('ZAR', 'ZAR', 'Rand');
    default:
      return const CurrencyInfo('XAF', 'FCFA', 'Franc CFA');
  }
}

/// Pays par défaut : déduit de la locale système, sinon Cameroun.
Country defaultCountry() {
  final cc = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  if (cc != null) {
    for (final c in kCountries) {
      if (c.code == cc) return c;
    }
  }
  return kCountries.first; // Cameroun
}
