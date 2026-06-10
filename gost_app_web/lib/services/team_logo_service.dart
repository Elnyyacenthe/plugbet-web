// ============================================================
// TeamLogoService — Resolution logos via TheSportsDB (API gratuite)
// ============================================================
// StatPal n'expose pas de logos. On enrichit cote client via :
//   GET https://www.thesportsdb.com/api/v1/json/3/searchteams.php?t={name}
// Reponse : { teams: [ { strTeam, strBadge, strSport, strLeague, ... } ] }
//
// Strategie :
// 1. Cache en memoire (Map<String, String?>) - hit instantane apres 1ere fois
//    Une valeur null = "fetch fait, pas trouve" -> evite re-fetch inutile
// 2. Pour matcher la bonne equipe parmi les homonymes (ex: 10 Arsenal) :
//    - Filtre par strSport (Soccer/Basketball)
//    - Skip variantes "U17/U19/U21/Women/Reserves/Youth"
//    - Prefere les equipes avec intLoved > 0 (popularite TheSportsDB)
//    - Sinon prend la 1ere
// 3. Lookup en background : BetTeamCrest affiche les initiales tout de
//    suite, puis rebuild quand le logo arrive (zero flicker).
// ============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logger.dart';
import 'statpal_service.dart' show Sport;

class TeamLogoService extends ChangeNotifier {
  TeamLogoService._() {
    _initBoxFuture = _initBox();
  }
  static final TeamLogoService instance = TeamLogoService._();

  static const _log = Logger('LOGOS');
  static const _boxName = 'team_logos_cache';
  // Version du cache : a bumper quand on change la logique de fetch
  // -> purge auto des negatifs au prochain demarrage.
  // v5 : passage par edge function team_logo_proxy (cache DB partage)
  // v6 : edge function distingue transient (timeout/429) du miss reel ;
  //      client cap concurrent=3 + TTL negatif 1j au lieu de 7j +
  //      pas de cache negatif si transient.
  static const _cacheVersion = 6;
  static const _versionKey = '__cache_version__';
  // Cap de concurrence des appels a l'edge function : evite de saturer
  // TheSportsDB et d'avoir un grand pourcentage de 429.
  static const _maxConcurrent = 3;

  /// LEGACY : ces overrides sont maintenant dans l'edge function
  /// `team_logo_proxy/index.ts`. Conserves ici en doc pour reference,
  /// mais NON utilises - tout est resolu cote serveur depuis v5.
  // ignore: unused_field
  static const Map<String, String> _nameOverrides = {
    // ── Cameroun (audience Plugbet) ──
    'coton sport': 'Cotonsport Garoua',
    'coton sport fc': 'Cotonsport Garoua',
    'union de douala': 'Union Douala',
    'pwd bamenda': 'PWD Bamenda',
    'canon yaounde': 'Canon Yaounde',
    'astres fc': 'Astres FC',
    'dragon club de yaounde': 'Dragon Yaounde',
    'eding sport': 'Eding Sport',
    'ums de loum': 'UMS Loum',
    'apejes academy': 'Apejes Mfou',
    'fovu de baham': 'Fovu Baham',
    // ── Senegal ──
    'as pikine': 'AS Pikine',
    'casa sport': 'Casa Sports',
    'genie de fatick': 'Genie',
    'jaraaf de dakar': 'Jaraaf',
    'us gorée': 'US Goree',
    // ── Cote d'Ivoire ──
    'asec mimosas': 'ASEC Mimosas',
    'africa sports': 'Africa Sports',
    'sewe sport': 'Sewe Sport',
    // ── Maghreb ──
    'wydad athletic club': 'Wydad Casablanca',
    'wydad ac': 'Wydad Casablanca',
    'raja club athletic': 'Raja Casablanca',
    'es tunis': 'Esperance Tunis',
    'esperance sportive de tunis': 'Esperance Tunis',
    'club africain': 'Club Africain Tunis',
    'al ahly': 'Al Ahly',
    'zamalek': 'Zamalek',
    // ── Top europe (variantes courantes StatPal) ──
    'fc barcelona': 'Barcelona',
    'fc bayern munchen': 'Bayern Munich',
    'fc bayern munich': 'Bayern Munich',
    'borussia dortmund': 'Borussia Dortmund',
    'paris saint germain': 'Paris Saint-Germain',
    'paris saint-germain fc': 'Paris Saint-Germain',
    'tottenham hotspur': 'Tottenham',
    'manchester city fc': 'Manchester City',
    'manchester united fc': 'Manchester United',
    'liverpool fc': 'Liverpool',
    'chelsea fc': 'Chelsea',
    'arsenal fc': 'Arsenal',
    'real madrid cf': 'Real Madrid',
    'real madrid c.f.': 'Real Madrid',
    'atletico de madrid': 'Atletico Madrid',
    'atletico madrid': 'Atletico Madrid',
    'fc internazionale milano': 'Inter Milan',
    'internazionale': 'Inter Milan',
    'inter milano': 'Inter Milan',
    'ac milan': 'AC Milan',
    'juventus fc': 'Juventus',
    'as roma': 'Roma',
    'ssc napoli': 'Napoli',
    // ── NBA (variantes courantes) ──
    'los angeles lakers': 'Los Angeles Lakers',
    'golden state warriors': 'Golden State Warriors',
    'la lakers': 'Los Angeles Lakers',
    'la clippers': 'Los Angeles Clippers',
    'ny knicks': 'New York Knicks',
    'phila 76ers': 'Philadelphia 76ers',
    // ── Pool virtuel matchs (Plugbet Virtual) ──
    'paris sg': 'Paris Saint-Germain',
    'olympique marseille': 'Marseille',
    'olympique lyonnais': 'Olympique Lyonnais',
    'monaco': 'AS Monaco',
    'ajax': 'Ajax',
    'benfica': 'SL Benfica',
    'porto': 'FC Porto',
    'sporting cp': 'Sporting CP',
    'flamengo': 'Flamengo',
    'river plate': 'River Plate',
    'boca juniors': 'Boca Juniors',
    'palmeiras': 'Palmeiras',
    'tp mazembe': 'TP Mazembe',
    'mamelodi sundowns': 'Mamelodi Sundowns',
    'esperance tunis': 'Esperance Tunis',
    'wydad casablanca': 'Wydad Casablanca',
    'al hilal': 'Al-Hilal',
    'al nassr': 'Al-Nassr',
    'newcastle': 'Newcastle',
    'aston villa': 'Aston Villa',
    'sevilla': 'Sevilla',
    'lazio': 'Lazio',
    'bayer leverkusen': 'Bayer Leverkusen',
    'rb leipzig': 'RB Leipzig',
  };
  // TTL des entrees null (pas trouve) : on retente apres 1j au cas ou
  // l'edge function ait reussi a fetcher entre temps. Les URLs trouvees
  // ne TTL pas (logos stables dans le temps).
  static const _negTtlDays = 1;

  final Map<String, String?> _cache = {};
  final Set<String> _inFlight = {};
  // File d'attente + compteur pour le cap de concurrence.
  final List<_PendingFetch> _queue = [];
  int _activeFetches = 0;
  late final Future<void> _initBoxFuture;
  Box? _box;

  Future<void> _initBox() async {
    try {
      _box = await Hive.openBox(_boxName);

      // Migration : si la version du cache a change, purge TOUS les
      // negatifs (les positifs restent valides). Permet d'invalider les
      // "pas trouve" obsoletes apres ameliorations de la logique fetch.
      final storedVersion = _box!.get(_versionKey);
      if (storedVersion != _cacheVersion) {
        final negativesToDelete = <dynamic>[];
        for (final k in _box!.keys) {
          if (k == _versionKey) continue;
          final v = _box!.get(k);
          if (v is Map) negativesToDelete.add(k);
        }
        for (final k in negativesToDelete) {
          await _box!.delete(k);
        }
        await _box!.put(_versionKey, _cacheVersion);
        _log.info('cache migration v$storedVersion->v$_cacheVersion : '
            '${negativesToDelete.length} negatifs purges');
      }

      // Hydrate le cache memoire depuis le disque
      final now = DateTime.now().millisecondsSinceEpoch;
      const negTtlMs = _negTtlDays * 24 * 3600 * 1000;
      final urlsToPrecache = <String>[];
      for (final k in _box!.keys) {
        if (k == _versionKey) continue;
        final v = _box!.get(k);
        if (v is String && v.isNotEmpty) {
          _cache[k.toString()] = v;
          urlsToPrecache.add(v);
        } else if (v is Map) {
          // entree negative {ts: ..., url: null}
          final ts = (v['ts'] as int?) ?? 0;
          if (now - ts < negTtlMs) {
            _cache[k.toString()] = null;
          } else {
            await _box!.delete(k);
          }
        }
      }
      _log.info('hydrated ${_cache.length} cached logos');
      notifyListeners();
      // PERF Web : precharge les images binaires dans le ImageCache Flutter
      // au boot. Cote mobile c'est instantane (CachedNetworkImage a deja
      // l'image sur disque). Cote Web : declenche le fetch HTTP dans le
      // browser cache (utilise les ETag/cache-control) AVANT que l'UI ne
      // mounte les widgets BetTeamCrest -> affichage instantane au mount.
      _precacheUrls(urlsToPrecache);
    } catch (e) {
      _log.warn('hive init error: $e');
    }
  }

  /// Precharge un batch d'URL dans le ImageCache global Flutter.
  /// Pas de BuildContext requis : on utilise NetworkImage.resolve().
  /// Cote Web : fait fetch HTTP en parallele (cap=8) -> mise en cache
  /// memoire du browser + Flutter image stream.
  /// Sur mobile : cache CachedNetworkImage prend deja le relais via cache disque.
  void _precacheUrls(List<String> urls) {
    if (urls.isEmpty) return;
    const cap = 8;
    var i = 0;
    var active = 0;
    final sw = Stopwatch()..start();
    var done = 0;
    void next() {
      while (active < cap && i < urls.length) {
        final u = urls[i++];
        active++;
        final stream = NetworkImage(u).resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (_, __) {
            active--;
            done++;
            stream.removeListener(listener);
            if (i >= urls.length && active == 0) {
              _log.info(
                  'precached $done/${urls.length} logos in ${sw.elapsedMilliseconds}ms');
            }
            next();
          },
          onError: (_, __) {
            active--;
            stream.removeListener(listener);
            next();
          },
        );
        stream.addListener(listener);
      }
    }
    next();
  }

  bool isResolved(String name, Sport sport) =>
      _cache.containsKey(_key(name, sport));

  String? getCached(String name, Sport sport) => _cache[_key(name, sport)];

  /// Attend que les requetes en cours se terminent (max timeout).
  /// Utile pour bloquer le loader initial du screen tant que tous les
  /// logos pertinents ne sont pas tous resolus (ou timeout).
  Future<void> waitForPending({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await _initBoxFuture;
    final deadline = DateTime.now().add(timeout);
    while (_inFlight.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  void prefetch(String name, Sport sport) {
    final k = _key(name, sport);
    if (_cache.containsKey(k) || _inFlight.contains(k)) return;
    _inFlight.add(k);
    _queue.add(_PendingFetch(name: name, sport: sport, key: k));
    _pump();
  }

  /// Lance le maximum de fetches possibles dans la limite du cap.
  void _pump() {
    while (_activeFetches < _maxConcurrent && _queue.isNotEmpty) {
      final p = _queue.removeAt(0);
      _activeFetches++;
      unawaited(_fetch(p.name, p.sport).then((res) async {
        _activeFetches--;
        _inFlight.remove(p.key);
        // Si transient (timeout/429), on NE met PAS l'entree en cache
        // memoire ni en cache disque : prochain prefetch retentera.
        if (!res.transient) {
          _cache[p.key] = res.url;
          await _initBoxFuture;
          try {
            if (res.url != null && res.url!.isNotEmpty) {
              await _box?.put(p.key, res.url);
              // PERF Web : declenche le precache image en background.
              // Au prochain mount BetTeamCrest, l'image sera deja en RAM.
              _precacheUrls([res.url!]);
            } else {
              await _box?.put(p.key, {
                'ts': DateTime.now().millisecondsSinceEpoch,
                'url': null,
              });
            }
          } catch (e) {
            _log.warn('hive write error for "${p.key}": $e');
          }
        }
        notifyListeners();
        // Lance la suite de la file
        _pump();
      }));
    }
  }

  /// LEGACY : normalisation maintenant cote edge function.
  /// Conserve ici pour reference mais non utilisee.
  // ignore: unused_element
  List<String> _variants(String name) {
    final out = <String>[];
    final seen = <String>{};
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      final k = t.toLowerCase();
      if (seen.add(k)) out.add(t);
    }

    // 0. Override manuel (priorite max)
    final norm = _stripAccents(name).toLowerCase().trim();
    final override = _nameOverrides[norm];
    if (override != null) add(override);

    // 1. Nom brut
    add(name);

    // 2. Strip articles/prepositions courantes (de, do, da, du, le, la, el, al)
    var stripped = name.replaceAll(
        RegExp(r'\b(de|do|da|du|le|la|les|el|al|of)\b', caseSensitive: false),
        ' ');
    stripped = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    add(stripped);

    // 3. Strip suffixes/prefixes club etendus (FC/SC/CF/AC/AS/KS/FK/CD/EC/NK/RC/SL/CR/CSKA)
    var cleaned = name
        .replaceAll(
            RegExp(
                r'\b(F\.?C\.?|S\.?C\.?|C\.?F\.?|A\.?C\.?|A\.?F\.?C\.?|U\.?S\.?L\.?|C\.?D\.?|F\.?K\.?|S\.?K\.?|N\.?K\.?|R\.?C\.?|E\.?C\.?|S\.?L\.?|A\.?S\.?|U\.?S\.?|K\.?S\.?|CSKA|CD|SC|FC|AC|CF|RC|RCD|CSD|FK|SK|NK|EC|SL|CR|AS|US|KS|KAA|GD|VFB|VFL|TSG)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    add(cleaned);

    // 4. Strip pays entre parentheses ("Arsenal (England)")
    var noCountry = name.replaceAll(RegExp(r'\s*\([^)]+\)\s*'), ' ').trim();
    add(noCountry);

    // 5. Accents -> ASCII (Bayern München -> Bayern Munchen)
    add(_stripAccents(name));
    add(_stripAccents(cleaned));
    add(_stripAccents(stripped));

    // 6. Strip et/and (Newcastle and Sunderland -> Newcastle Sunderland)
    add(name.replaceAll(RegExp(r'\s+(and|et|&)\s+', caseSensitive: false), ' '));

    // 7. 1er mot seulement (derniere chance pour noms exotiques)
    final firstWord = name.split(RegExp(r'\s+')).first;
    if (firstWord.length >= 4) add(firstWord);

    return out;
  }

  // ignore: unused_element
  String _stripAccents(String s) {
    const a = 'àáâãäåèéêëìíîïòóôõöùúûüñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÑÇ';
    const b = 'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final idx = a.indexOf(ch);
      sb.write(idx >= 0 ? b[idx] : ch);
    }
    return sb.toString();
  }

  /// Appelle l'edge function `team_logo_proxy` qui :
  ///  1. Cherche dans le cache DB partage (table team_logo_cache)
  ///  2. Si miss : appelle TheSportsDB cote serveur (1 caller global)
  ///  3. Sauvegarde le resultat en DB pour tous les autres users
  ///
  /// Retourne {url, transient}. Si transient=true, le client NE met PAS
  /// en cache negatif et retentera au prochain prefetch.
  Future<_FetchResult> _fetch(String name, Sport sport) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('team_logo_proxy', body: {
        'sport': sport == Sport.basketball ? 'basketball' : 'soccer',
        'name': name,
      });
      if (res.status != 200) {
        _log.warn('team_logo_proxy HTTP ${res.status} for "$name"');
        // HTTP error cote Supabase = transient (retry plus tard)
        return const _FetchResult(url: null, transient: true);
      }
      final data = res.data;
      if (data is Map) {
        final transient = data['transient'] == true;
        final url = data['url'];
        if (url is String && url.isNotEmpty) {
          return _FetchResult(url: url, transient: false);
        }
        return _FetchResult(url: null, transient: transient);
      }
      return const _FetchResult(url: null, transient: false);
    } catch (e) {
      _log.warn('team_logo_proxy error "$name": $e');
      // Erreur reseau cote client = transient
      return const _FetchResult(url: null, transient: true);
    }
  }

  String _key(String name, Sport sport) =>
      '${sport.name}:${name.trim().toLowerCase()}';
}

class _PendingFetch {
  final String name;
  final Sport sport;
  final String key;
  const _PendingFetch({required this.name, required this.sport, required this.key});
}

class _FetchResult {
  final String? url;
  final bool transient;
  const _FetchResult({required this.url, required this.transient});
}
