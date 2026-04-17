// ============================================================
// Env — Variables d'environnement centralisees
// A terme : remplacer par `flutter_dotenv` ou `--dart-define`
// ============================================================

class Env {
  /// Supabase
  static const String supabaseUrl =
      String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dqzrociaaztlezwlgzwh.supabase.co',
  );

  static const String supabaseAnonKey =
      String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxenJvY2lhYXp0bGV6d2xnendoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk4NTI5MDgsImV4cCI6MjA4NTQyODkwOH0.8anJU1zgZgAaGbAS33Byh_AMRGew5qMgaAKEk5FDiKk',
  );

  /// APIs Football
  /// Note: dans une vraie prod, passer par une Edge Function Supabase
  /// qui proxifie football-data.org et ne fuite pas la cle.
  static const String footballDataApiKey =
      String.fromEnvironment(
    'FOOTBALL_DATA_API_KEY',
    defaultValue: '5bb26437b46b43689663390841d6f469',
  );

  static const String apiSportsKey =
      String.fromEnvironment(
    'API_SPORTS_KEY',
    defaultValue: 'd15a7ed3db45d031275651a2fc70f7456b42f02f88f740f2086fcf9b716eeab7',
  );

  /// Gemini (optional)
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  /// Flags
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
}
