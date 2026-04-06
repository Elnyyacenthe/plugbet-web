import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'services/hive_service.dart';
import 'services/supabase_service.dart';
import 'services/api_sports_service.dart';
import 'services/api_football_service.dart';
import 'services/live_score_manager.dart';
import 'providers/matches_provider.dart';
import 'providers/favorites_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/games_screen.dart';
import 'providers/messaging_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/player_provider.dart';
import 'widgets/drawer_menu.dart';
import 'ludo/providers/ludo_provider.dart';
import 'ludo/services/audio_service.dart';
import 'services/notification_service.dart';
import 'fantasy/providers/fpl_provider.dart';
import 'fantasy/screens/fantasy_home_screen.dart';

/// Contourne le problème de certificats SSL sur Android 7.0+
/// Les anciens appareils n'ont pas les certificats racine récents
class PlugbetHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fix SSL pour Android 7.0 (certificats obsolètes)
  if (!kIsWeb) {
    HttpOverrides.global = PlugbetHttpOverrides();
  }

  // Forcer le mode portrait + barre d'état transparente
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // --- 1. Initialiser Hive (stockage local) ---
  await HiveService.initHive();
  final hiveService = HiveService();
  await hiveService.openBoxes();

  // --- 2. Initialiser Supabase (timeout court pour ne pas bloquer le démarrage) ---
  try {
    await SupabaseService.initialize().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('Supabase init ignoré (timeout ou non configuré) : $e');
  }
  final supabaseService = SupabaseService();

  // Connexion anonyme (non bloquante)
  supabaseService.signInAnonymously();

  // --- Audio Ludo ---
  AudioService.instance.init();

  // --- Notifications locales ---
  NotificationService.instance.init();
  NotificationService.instance.requestPermission();

  // --- 3. Services API Football ---
  const defaultApiKey = 'd15a7ed3db45d031275651a2fc70f7456b42f02f88f740f2086fcf9b716eeab7';
  final apiSportsService = ApiSportsService(
    apiKey: hiveService.getApiSportsKey() ?? defaultApiKey,
  );
  final apiService = ApiFootballService();

  // --- 4. Live Score Manager ---
  final liveScoreManager = LiveScoreManager(apiService);

  // --- 5. Lancer l'app ---
  runApp(
    PlugbetApp(
      hiveService: hiveService,
      supabaseService: supabaseService,
      apiSportsService: apiSportsService,
      apiService: apiService,
      liveScoreManager: liveScoreManager,
    ),
  );
}

class PlugbetApp extends StatelessWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;
  final ApiSportsService apiSportsService;
  final ApiFootballService apiService;
  final LiveScoreManager liveScoreManager;

  const PlugbetApp({
    super.key,
    required this.hiveService,
    required this.supabaseService,
    required this.apiSportsService,
    required this.apiService,
    required this.liveScoreManager,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(hiveService),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => MatchesProvider(
            apiSportsService: apiSportsService,
            apiService: apiService,
            hiveService: hiveService,
            supabaseService: supabaseService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => FavoritesProvider(
            hiveService: hiveService,
            supabaseService: supabaseService,
          )..loadFavorites(),
        ),
        ChangeNotifierProvider(
          create: (_) => LudoProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => MessagingProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => WalletProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => FplProvider(),
        ),
        ChangeNotifierProvider.value(
          value: liveScoreManager,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProv, child) {
          // Mettre à jour _isDark AVANT le build pour que les getters soient corrects
          AppColors.updateBrightness(
            themeProv.isDark ? Brightness.dark : Brightness.light,
          );
          return MaterialApp(
            // Key forcée : reconstruit tout l'arbre quand le thème change
            key: ValueKey(themeProv.isDark),
            title: 'Plugbet',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProv.mode,
            builder: (ctx, widget) {
              return MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: TextScaler.linear(themeProv.textScaleFactor),
                ),
                child: widget!,
              );
            },
            home: child!,
          );
        },
        child: _AppEntry(
          hiveService: hiveService,
          supabaseService: supabaseService,
          liveScoreManager: liveScoreManager,
        ),
      ),
    );
  }
}

/// Gère la transition Splash → Main
class _AppEntry extends StatefulWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;
  final LiveScoreManager liveScoreManager;

  const _AppEntry({
    required this.hiveService,
    required this.supabaseService,
    required this.liveScoreManager,
  });

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onInit: () async {
          // Les matchs se chargent déjà depuis le constructeur du provider.
          // On attend que le cache soit affiché (quasi instantané) puis on continue.
          // PAS de spin-loop : ça bloque le thread UI sur Huawei.
          final provider = context.read<MatchesProvider>();
          // Si le cache est déjà chargé, on peut partir tout de suite
          if (provider.allMatches.isNotEmpty) return;
          // Sinon attendre max 2s avec des pauses longues (pas de spin-loop)
          for (int i = 0; i < 4; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (provider.state != LoadingState.idle &&
                provider.state != LoadingState.loading) {
              break;
            }
          }
        },
        onReady: () {
          if (mounted) {
            setState(() => _showSplash = false);
            // Démarrer le tracking des scores en direct après le splash
            widget.liveScoreManager.startLiveTracking();
          }
        },
      );
    }

    return MainShell(
      hiveService: widget.hiveService,
      supabaseService: widget.supabaseService,
      liveScoreManager: widget.liveScoreManager,
    );
  }
}

// ============================================================
// Shell principal avec BottomNavigationBar
// 6 onglets : Matchs, Favoris, Fantasy, Jeux, Chat, Réglages
// ============================================================
class MainShell extends StatefulWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;
  final LiveScoreManager liveScoreManager;

  const MainShell({
    super.key,
    required this.hiveService,
    required this.supabaseService,
    required this.liveScoreManager,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final MatchesProvider _matchesProvider;

  // Lazy loading des écrans
  final Map<int, Widget> _cachedScreens = {};

  // Suivi des scores précédents pour détecter les buts
  final Map<int, ({int home, int away})> _prevScores = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _matchesProvider = context.read<MatchesProvider>();
      _matchesProvider.listenToRealtimeUpdates();
      _matchesProvider.addListener(_detectGoals);
      // Lier le wallet (coins) au module Fantasy
      context.read<FplProvider>().attachWallet(context.read<WalletProvider>());
    });
  }

  /// Compare les scores actuels aux précédents pour générer des notifications but
  void _detectGoals() {
    if (!mounted) return;
    final matches = context.read<MatchesProvider>().allMatches;
    final notifProvider = context.read<NotificationProvider>();

    for (final match in matches) {
      if (!match.status.isLive) continue;
      final home = match.score.homeFullTime ?? 0;
      final away = match.score.awayFullTime ?? 0;
      final prev = _prevScores[match.id];

      if (prev != null) {
        if (home > prev.home) {
          notifProvider.addGoal(
            match.homeTeam.shortName,
            match.awayTeam.shortName,
            home, away,
          );
        } else if (away > prev.away) {
          notifProvider.addGoal(
            match.homeTeam.shortName,
            match.awayTeam.shortName,
            home, away,
          );
        }
      }
      _prevScores[match.id] = (home: home, away: away);
    }
  }

  Widget _buildScreen(int index) {
    // Construire l'écran seulement lors de la première navigation
    return _cachedScreens.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return HomeScreen(scaffoldKey: _scaffoldKey);
        case 1:
          return const FantasyHomeScreen();
        case 2:
          return const GamesScreen();
        case 3:
          return const ChatScreen();
        case 4:
          return const ProfileScreen();
        case 5:
          return SettingsScreen(
            hiveService: widget.hiveService,
            supabaseService: widget.supabaseService,
          );
        default:
          return SizedBox();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _matchesProvider.removeListener(_detectGoals);
    super.dispose();
  }

  /// Gérer le cycle de vie de l'app (foreground / background)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<MatchesProvider>();
    switch (state) {
      case AppLifecycleState.resumed:
        provider.setAppForeground(true);
        // Marquer en ligne
        try { context.read<MessagingProvider>().goOnline(); } catch (_) {}
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        provider.setAppForeground(false);
        // Marquer hors ligne
        try { context.read<MessagingProvider>().goOffline(); } catch (_) {}
        break;
    }

    // Informer le LiveScoreManager des changements de cycle de vie
    widget.liveScoreManager.onAppLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        onTabChange: (i) => setState(() => _currentIndex = i),
      ),
      body: _buildScreen(_currentIndex),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDark,
          border: Border(
            top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.sports_soccer_outlined),
              activeIcon: Icon(Icons.sports_soccer),
              label: 'Matchs',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events_outlined),
              activeIcon: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppColors.neonGreen, AppColors.neonYellow],
                ).createShader(bounds),
                child: Icon(Icons.emoji_events, color: Colors.white),
              ),
              label: 'Fantasy',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sports_esports_outlined),
              activeIcon: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppColors.neonGreen, AppColors.neonYellow],
                ).createShader(bounds),
                child: Icon(Icons.sports_esports, color: Colors.white),
              ),
              label: 'Jeux',
            ),
            BottomNavigationBarItem(
              icon: Consumer<MessagingProvider>(
                builder: (_, msg, __) {
                  final count = msg.unreadTotal;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count', style: TextStyle(fontSize: 9)),
                    backgroundColor: AppColors.neonRed,
                    child: Icon(Icons.chat_bubble_outline),
                  );
                },
              ),
              activeIcon: Consumer<MessagingProvider>(
                builder: (_, msg, __) {
                  final count = msg.unreadTotal;
                  return Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count', style: TextStyle(fontSize: 9)),
                    backgroundColor: AppColors.neonRed,
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [AppColors.neonBlue, AppColors.neonPurple],
                      ).createShader(bounds),
                      child: Icon(Icons.chat_bubble, color: Colors.white),
                    ),
                  );
                },
              ),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppColors.neonBlue, AppColors.neonGreen],
                ).createShader(bounds),
                child: Icon(Icons.person, color: Colors.white),
              ),
              label: 'Profil',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Réglages',
            ),
          ],
        ),
      ),
    );
  }
}
