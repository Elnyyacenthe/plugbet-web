// ============================================================
// Plugbet – Ecran d'authentification complet
// Connexion + Inscription avec username
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/supabase_service.dart';
import '../ludo/providers/ludo_provider.dart';

class AuthScreen extends StatefulWidget {
  /// Si true, affiche le mode inscription par defaut
  final bool startWithSignUp;

  const AuthScreen({super.key, this.startWithSignUp = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late bool _isSignUp;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.startWithSignUp;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    _animController.reverse().then((_) {
      setState(() {
        _isSignUp = !_isSignUp;
        _errorMessage = null;
      });
      _animController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                SizedBox(height: 20),

                // Bouton retour
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),

                SizedBox(height: 20),

                // Logo / Header
                _buildHeader(),

                SizedBox(height: 40),

                // Formulaire
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _buildForm(),
                ),

                SizedBox(height: 40),

                // Toggle inscription/connexion
                _buildToggle(),

                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final t = AppLocalizations.of(context)!;
    return Column(
      children: [
        // Icone animee
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _isSignUp
                  ? [AppColors.neonBlue, AppColors.neonPurple]
                  : [AppColors.neonGreen, AppColors.neonBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isSignUp ? AppColors.neonBlue : AppColors.neonGreen)
                    .withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
        SizedBox(height: 24),
        Text(
          _isSignUp ? t.authSignUp : 'Bienvenue',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 8),
        Text(
          _isSignUp
              ? 'Inscrivez-vous pour jouer au Ludo et gagner des coins'
              : 'Connectez-vous pour acceder au multijoueur',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final t = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Erreur
          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.neonRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.neonRed, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: AppColors.neonRed, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          // Username (inscription uniquement)
          if (_isSignUp) ...[
            _buildField(
              controller: _usernameController,
              hint: 'Nom d\'utilisateur',
              icon: Icons.person_outline,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Entrez un nom d\'utilisateur';
                }
                if (val.trim().length < 3) {
                  return 'Minimum 3 caracteres';
                }
                return null;
              },
            ),
            SizedBox(height: 14),
          ],

          // Email
          _buildField(
            controller: _emailController,
            hint: t.authEmail,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Entrez votre email';
              }
              if (!val.contains('@') || !val.contains('.')) {
                return 'Email invalide';
              }
              return null;
            },
          ),
          SizedBox(height: 14),

          // Mot de passe
          _buildField(
            controller: _passwordController,
            hint: t.authPassword,
            icon: Icons.lock_outline,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Entrez votre mot de passe';
              }
              if (val.length < 6) {
                return 'Minimum 6 caracteres';
              }
              return null;
            },
          ),

          // Mot de passe oublie (seulement en mode connexion)
          if (!_isSignUp) ...[
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _handleForgotPassword,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  t.authForgotPassword,
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],

          SizedBox(height: 20),

          // Bouton principal
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSignUp ? AppColors.neonBlue : AppColors.neonGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.bgElevated,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isSignUp ? Icons.person_add : Icons.login,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          _isSignUp ? t.authSignUp : t.authSignIn,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // Bonus inscription : info coins
          if (_isSignUp) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bonus : 500 coins offerts a l\'inscription !',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: _isSignUp ? AppColors.neonBlue : AppColors.neonGreen,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.neonRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.neonRed, width: 1.5),
        ),
        errorStyle: TextStyle(color: AppColors.neonRed, fontSize: 11),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildToggle() {
    final t = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? 'Deja un compte ?' : 'Pas encore de compte ?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        TextButton(
          onPressed: _isLoading ? null : _toggleMode,
          child: Text(
            _isSignUp ? t.authSignIn : t.authSignUp,
            style: TextStyle(
              color: _isSignUp ? AppColors.neonGreen : AppColors.neonBlue,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Entrez votre email d\'abord');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await SupabaseService().sendPasswordResetEmail(email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Email de reinitialisation envoye a $email'),
          backgroundColor: AppColors.neonGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      setState(() => _errorMessage = error);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final supabase = SupabaseService();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isSignUp) {
        // Inscription
        final (result, error) = await supabase.signUpWithEmail(email, password);

        if (error != null) {
          setState(() => _errorMessage = error);
        } else if (result != null) {
          // Mettre a jour le username dans le profil
          final username = _usernameController.text.trim();
          if (username.isNotEmpty && supabase.currentUserId != null) {
            try {
              final ludo = context.read<LudoProvider>();
              await ludo.loadProfile();
              await ludo.updateUsername(username);
            } catch (_) {}
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Compte cree avec succes !'),
                  ],
                ),
                backgroundColor: AppColors.neonGreen,
                behavior: SnackBarBehavior.floating,
              ),
            );

            // Rafraichir le profil Ludo et revenir
            context.read<LudoProvider>().loadProfile();
            Navigator.pop(context, true); // true = auth reussie
          }
        }
      } else {
        // Connexion
        final (result, error) = await supabase.signInWithEmail(email, password);

        if (error != null) {
          setState(() => _errorMessage = error);
        } else if (result != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Connexion reussie !'),
                  ],
                ),
                backgroundColor: AppColors.neonGreen,
                behavior: SnackBarBehavior.floating,
              ),
            );

            context.read<LudoProvider>().loadProfile();
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur inattendue : $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
