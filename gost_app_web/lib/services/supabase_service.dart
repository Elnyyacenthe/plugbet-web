// ============================================================
// Plugbet – Service Supabase
// Gère : Auth anonyme, sync matchs realtime, sync favoris
// ============================================================
// SETUP SUPABASE :
// 1. Créer un projet sur https://supabase.com (plan gratuit)
// 2. Récupérer l'URL et la clé anon dans Settings > API
// 3. Exécuter le SQL ci-dessous dans SQL Editor :
//
// ------- SQL SCHEMA -------
// create table public.matches (
//   id bigint primary key,
//   competition_id int,
//   competition_name text,
//   home_team_id int,
//   home_team_name text,
//   away_team_id int,
//   away_team_name text,
//   home_score int default 0,
//   away_score int default 0,
//   status text default 'SCHEDULED',
//   minute int,
//   utc_date timestamptz,
//   events jsonb default '[]'::jsonb,
//   updated_at timestamptz default now()
// );
//
// -- Activer le Realtime sur cette table :
// alter publication supabase_realtime add table public.matches;
//
// -- Table des favoris utilisateurs :
// create table public.user_favorites (
//   id uuid default gen_random_uuid() primary key,
//   user_id uuid references auth.users(id) on delete cascade,
//   team_id int not null,
//   created_at timestamptz default now(),
//   unique(user_id, team_id)
// );
//
// -- Activer RLS (Row Level Security) :
// alter table public.user_favorites enable row level security;
//
// create policy "Users can manage their own favorites"
//   on public.user_favorites
//   for all
//   using (auth.uid() = user_id)
//   with check (auth.uid() = user_id);
//
// -- Politique publique pour la table matches (lecture seule) :
// alter table public.matches enable row level security;
//
// create policy "Anyone can read matches"
//   on public.matches
//   for select
//   using (true);
// ------- FIN SQL -------
// ============================================================

import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/football_models.dart';

class SupabaseService {
  // --- REMPLACER PAR VOS VALEURS ---
  static const String supabaseUrl = 'https://dqzrociaaztlezwlgzwh.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxenJvY2lhYXp0bGV6d2xnendoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk4NTI5MDgsImV4cCI6MjA4NTQyODkwOH0.8anJU1zgZgAaGbAS33Byh_AMRGew5qMgaAKEk5FDiKk';

  late final SupabaseClient _client;
  StreamSubscription? _matchesSubscription;

  /// Initialisation (appelée dans main.dart)
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  SupabaseService() {
    _client = Supabase.instance.client;
  }

  SupabaseClient get client => _client;

  // ============================================================
  // AUTH – Connexion anonyme
  // ============================================================
  Future<void> signInAnonymously() async {
    try {
      if (_client.auth.currentSession == null) {
        await _client.auth.signInAnonymously();
      }
    } catch (e) {
      // En mode offline, on continue sans auth
    }
  }

  /// Connexion email/password (optionnel, pour sync multi-device)
  /// Retourne (AuthResponse?, errorMessage?)
  Future<(AuthResponse?, String?)> signInWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return (response, null);
    } on AuthException catch (e) {
      return (null, _translateAuthError(e.message));
    } catch (e) {
      return (null, 'Erreur de connexion : $e');
    }
  }

  /// Envoie un email de reinitialisation de mot de passe.
  /// Retourne null en cas de succes, ou le message d'erreur.
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return _translateAuthError(e.message);
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Change le mot de passe de l'utilisateur connecte.
  /// Retourne null en cas de succes, ou le message d'erreur.
  Future<String?> changePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return _translateAuthError(e.message);
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Inscription email/password
  Future<(AuthResponse?, String?)> signUpWithEmail(String email, String password) async {
    try {
      final response = await _client.auth.signUp(email: email, password: password);
      return (response, null);
    } on AuthException catch (e) {
      return (null, _translateAuthError(e.message));
    } catch (e) {
      return (null, 'Erreur d\'inscription : $e');
    }
  }

  // ============================================================
  // AUTH – Compte rapide (username + password, sans vrai email)
  // ============================================================
  /// Cree un compte avec un email genere (username@plugbet.local)
  Future<(AuthResponse?, String?)> quickSignUp(String username, String password) async {
    final fakeEmail = '${username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}@plugbet.local';
    try {
      final response = await _client.auth.signUp(
        email: fakeEmail,
        password: password,
        data: {'username': username, 'account_type': 'quick'},
      );
      return (response, null);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already') || msg.contains('registered')) {
        return (null, 'Ce nom d\'utilisateur est deja pris');
      }
      return (null, _translateAuthError(e.message));
    } catch (e) {
      return (null, 'Erreur: $e');
    }
  }

  /// Connexion compte rapide
  Future<(AuthResponse?, String?)> quickSignIn(String username, String password) async {
    final fakeEmail = '${username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}@plugbet.local';
    return signInWithEmail(fakeEmail, password);
  }

  // ============================================================
  // AUTH – Google Sign-In (google_sign_in v7+)
  // ============================================================
  /// Web/Server client ID (configurer dans Google Cloud Console + Supabase)
  static const _googleServerClientId = ''; // TODO: ajouter ton server client ID

  /// Initialise GoogleSignIn une seule fois.
  static bool _googleInitialized = false;
  Future<void> _ensureGoogleInit() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId.isEmpty ? null : _googleServerClientId,
    );
    _googleInitialized = true;
  }

  Future<(AuthResponse?, String?)> signInWithGoogle() async {
    try {
      await _ensureGoogleInit();

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        return (null, 'Erreur Google: impossible de recuperer le token');
      }

      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      // Marquer comme compte Google
      await _client.auth.updateUser(UserAttributes(
        data: {'account_type': 'google'},
      ));

      return (response, null);
    } on AuthException catch (e) {
      return (null, _translateAuthError(e.message));
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancel') || msg.contains('aborted')) {
        return (null, null); // user cancelled
      }
      return (null, 'Erreur Google: $e');
    }
  }

  // ============================================================
  // AUTH – Phone OTP
  // ============================================================
  /// Envoie un OTP au numero de telephone.
  /// Le format doit etre international (+237..., +33..., etc.)
  Future<String?> sendPhoneOtp(String phone) async {
    try {
      await _client.auth.signInWithOtp(phone: phone);
      return null;
    } on AuthException catch (e) {
      return _translateAuthError(e.message);
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Verifie l'OTP et connecte l'utilisateur
  Future<(AuthResponse?, String?)> verifyPhoneOtp(String phone, String otp) async {
    try {
      final response = await _client.auth.verifyOTP(
        phone: phone,
        token: otp,
        type: OtpType.sms,
      );
      return (response, null);
    } on AuthException catch (e) {
      return (null, _translateAuthError(e.message));
    } catch (e) {
      return (null, 'Erreur: $e');
    }
  }

  // ============================================================
  // AUTH – Upgrade compte officiel
  // ============================================================
  /// Met a jour les infos du profil pour le transformer en compte officiel.
  /// email, phone, fullName sont optionnels et ne modifient que s'ils sont fournis.
  Future<String?> upgradeToOfficialAccount({
    String? email,
    String? phone,
    String? fullName,
  }) async {
    try {
      final attrs = UserAttributes(
        email: email,
        phone: phone,
        data: {
          if (fullName != null) 'full_name': fullName,
          'account_type': 'official',
        },
      );
      await _client.auth.updateUser(attrs);
      return null;
    } on AuthException catch (e) {
      return _translateAuthError(e.message);
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Type de compte actuel (quick, official, google, phone, null)
  String? get accountType {
    final meta = _client.auth.currentUser?.userMetadata;
    return meta?['account_type'] as String?;
  }

  String _translateAuthError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login credentials') || lower.contains('invalid_credentials')) {
      return 'Email ou mot de passe incorrect';
    }
    if (lower.contains('email not confirmed')) {
      return 'Veuillez confirmer votre email avant de vous connecter';
    }
    if (lower.contains('user already registered') || lower.contains('already been registered')) {
      return 'Cet email est déjà inscrit. Essayez de vous connecter.';
    }
    if (lower.contains('password')) {
      return 'Le mot de passe doit contenir au moins 6 caractères';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Adresse email invalide';
    }
    if (lower.contains('email') && lower.contains('format')) {
      return 'Format d\'adresse email invalide';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Erreur réseau. Vérifiez votre connexion internet.';
    }
    return msg;
  }

  /// Déconnexion
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// User ID courant
  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // MATCHS – Upsert et lecture
  // ============================================================

  /// Mettre à jour un match dans Supabase (quand le polling détecte un changement)
  Future<void> upsertMatch(FootballMatch match) async {
    try {
      await _client.from('matches').upsert({
        'id': match.id,
        'competition_id': match.competition.id,
        'competition_name': match.competition.name,
        'home_team_id': match.homeTeam.id,
        'home_team_name': match.homeTeam.name,
        'away_team_id': match.awayTeam.id,
        'away_team_name': match.awayTeam.name,
        'home_score': match.score.homeFullTime ?? 0,
        'away_score': match.score.awayFullTime ?? 0,
        'status': match.statusStr,
        'minute': match.minute,
        'utc_date': match.utcDate,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Silencieux en cas d'erreur (mode offline)
    }
  }

  /// Batch upsert pour plusieurs matchs
  Future<void> upsertMatches(List<FootballMatch> matches) async {
    try {
      final rows = matches.map((m) => {
        'id': m.id,
        'competition_id': m.competition.id,
        'competition_name': m.competition.name,
        'home_team_id': m.homeTeam.id,
        'home_team_name': m.homeTeam.name,
        'away_team_id': m.awayTeam.id,
        'away_team_name': m.awayTeam.name,
        'home_score': m.score.homeFullTime ?? 0,
        'away_score': m.score.awayFullTime ?? 0,
        'status': m.statusStr,
        'minute': m.minute,
        'utc_date': m.utcDate,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();
      await _client.from('matches').upsert(rows);
    } catch (e) {
      // Silencieux
    }
  }

  // ============================================================
  // REALTIME – Écouter les changements de score
  // ============================================================

  /// S'abonner aux modifications de la table matches
  /// Le callback reçoit la map complète du match modifié
  void subscribeToMatchUpdates(
    void Function(Map<String, dynamic> payload) onUpdate,
  ) {
    _matchesSubscription?.cancel();
    _client
        .channel('public:matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            onUpdate(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Se désabonner
  void unsubscribeFromMatchUpdates() {
    _matchesSubscription?.cancel();
    _client.removeAllChannels();
  }

  // ============================================================
  // FAVORIS – Sync avec Supabase
  // ============================================================

  /// Récupérer les favoris de l'utilisateur depuis Supabase
  Future<List<int>> fetchFavoriteTeamIds() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('user_favorites')
          .select('team_id')
          .eq('user_id', userId);
      return (response as List)
          .map((row) => row['team_id'] as int)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Ajouter un favori sur Supabase
  Future<void> addFavoriteTeam(int teamId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _client.from('user_favorites').upsert({
        'user_id': userId,
        'team_id': teamId,
      });
    } catch (e) {
      // Silencieux
    }
  }

  /// Supprimer un favori sur Supabase
  Future<void> removeFavoriteTeam(int teamId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await _client
          .from('user_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('team_id', teamId);
    } catch (e) {
      // Silencieux
    }
  }

  /// Nettoyage
  void dispose() {
    unsubscribeFromMatchUpdates();
  }
}
