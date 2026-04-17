// ============================================================
// Plugbet – Ecran d'authentification complet
// 4 modes : Compte rapide, Email, Google, Telephone (OTP)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/supabase_service.dart';
import '../ludo/providers/ludo_provider.dart';

class AuthScreen extends StatefulWidget {
  final bool startWithSignUp;
  const AuthScreen({super.key, this.startWithSignUp = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { quick, email, phone }

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late bool _isSignUp;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  _AuthMode _mode = _AuthMode.quick;

  // Phone OTP
  bool _otpSent = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
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
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    _animController.reverse().then((_) {
      setState(() {
        _mode = mode;
        _errorMessage = null;
        _otpSent = false;
      });
      _animController.forward();
    });
  }

  void _toggleMode() {
    _animController.reverse().then((_) {
      setState(() {
        _isSignUp = !_isSignUp;
        _errorMessage = null;
        _otpSent = false;
      });
      _animController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ),
                SizedBox(height: 16),
                _buildHeader(t),
                SizedBox(height: 28),
                // Mode selector
                _buildModeSelector(t),
                SizedBox(height: 24),
                // Google button (toujours visible)
                _buildGoogleButton(t),
                SizedBox(height: 16),
                _buildDivider(t),
                SizedBox(height: 16),
                // Form
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _mode == _AuthMode.phone
                      ? _buildPhoneForm(t)
                      : _buildCredentialForm(t),
                ),
                SizedBox(height: 24),
                _buildToggle(t),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════════════════
  Widget _buildHeader(AppLocalizations t) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _isSignUp
                  ? [AppColors.neonBlue, AppColors.neonPurple]
                  : [AppColors.neonGreen, AppColors.neonBlue],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isSignUp ? AppColors.neonBlue : AppColors.neonGreen)
                    .withValues(alpha: 0.4),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(
            _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        SizedBox(height: 16),
        Text(
          _isSignUp ? t.authSignUp : t.authWelcome,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // MODE SELECTOR (Quick / Email / Phone)
  // ════════════════════════════════════════════════════════════
  Widget _buildModeSelector(AppLocalizations t) {
    return Row(
      children: [
        _modeChip(t.authQuickAccount, Icons.flash_on, _AuthMode.quick, AppColors.neonYellow),
        SizedBox(width: 8),
        _modeChip('Email', Icons.email_outlined, _AuthMode.email, AppColors.neonBlue),
        SizedBox(width: 8),
        _modeChip(t.authPhoneSignIn.replaceAll('Continuer avec ', '').replaceAll('Continue with ', ''),
            Icons.phone_android, _AuthMode.phone, AppColors.neonGreen),
      ],
    );
  }

  Widget _modeChip(String label, IconData icon, _AuthMode mode, Color color) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : AppColors.divider,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? color : AppColors.textMuted),
              SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? color : AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // GOOGLE BUTTON
  // ════════════════════════════════════════════════════════════
  Widget _buildGoogleButton(AppLocalizations t) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Image.asset('assets/google_logo.png', width: 20, height: 20,
            errorBuilder: (_, __, ___) => Icon(Icons.g_mobiledata, size: 24, color: Colors.red)),
        label: Text(t.authGoogleSignIn,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }

  Widget _buildDivider(AppLocalizations t) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(t.authOr,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // CREDENTIAL FORM (Quick + Email)
  // ════════════════════════════════════════════════════════════
  Widget _buildCredentialForm(AppLocalizations t) {
    final isQuick = _mode == _AuthMode.quick;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Error
          if (_errorMessage != null) ...[
            _errorBox(),
            SizedBox(height: 14),
          ],

          // Username (inscription quick ou email)
          if (_isSignUp) ...[
            _field(
              controller: _usernameController,
              hint: isQuick ? t.authPseudo : t.authUsername,
              icon: Icons.person_outline,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return t.authPseudo;
                if (v.trim().length < 3) return t.profilePasswordTooShort;
                return null;
              },
            ),
            SizedBox(height: 12),
          ],

          // Username for quick login
          if (!_isSignUp && isQuick) ...[
            _field(
              controller: _usernameController,
              hint: t.authPseudo,
              icon: Icons.person_outline,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return t.authPseudo;
                return null;
              },
            ),
            SizedBox(height: 12),
          ],

          // Email (only for email mode)
          if (!isQuick) ...[
            _field(
              controller: _emailController,
              hint: t.authEmail,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return t.authEmail;
                if (!v.contains('@') || !v.contains('.')) return t.authEmail;
                return null;
              },
            ),
            SizedBox(height: 12),
          ],

          // Password
          _field(
            controller: _passwordController,
            hint: t.authPassword,
            icon: Icons.lock_outline,
            obscure: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.textMuted,
                size: 20,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return t.authPassword;
              if (v.length < 6) return t.profilePasswordTooShort;
              return null;
            },
          ),

          // Forgot password (email mode, login only)
          if (!_isSignUp && !isQuick) ...[
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
                child: Text(t.authForgotPassword,
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ],

          SizedBox(height: 20),

          // Submit
          _submitButton(t, isQuick),

          // Bonus coins
          if (_isSignUp) ...[
            SizedBox(height: 14),
            _bonusCoinsRow(t),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // PHONE FORM
  // ════════════════════════════════════════════════════════════
  Widget _buildPhoneForm(AppLocalizations t) {
    return Column(
      children: [
        if (_errorMessage != null) ...[
          _errorBox(),
          SizedBox(height: 14),
        ],

        if (!_otpSent) ...[
          // Phone number input
          _field(
            controller: _phoneController,
            hint: t.authPhoneHint,
            icon: Icons.phone_android,
            keyboardType: TextInputType.phone,
          ),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleSendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Icon(Icons.send, size: 18),
              label: Text(t.authSendOtp,
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ] else ...[
          // OTP sent confirmation
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.neonGreen, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                      t.authOtpSent(_phoneController.text.trim()),
                      style: TextStyle(
                          color: AppColors.neonGreen, fontSize: 13)),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          _field(
            controller: _otpController,
            hint: t.authOtpCode,
            icon: Icons.pin,
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleVerifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Icon(Icons.verified, size: 18),
              label: Text(t.authVerify,
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════════
  // WIDGETS HELPERS
  // ════════════════════════════════════════════════════════════
  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neonRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.neonRed, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style: TextStyle(color: AppColors.neonRed, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _field({
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
          borderSide: BorderSide(color: AppColors.neonGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.neonRed),
        ),
        errorStyle: TextStyle(color: AppColors.neonRed, fontSize: 11),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _submitButton(AppLocalizations t, bool isQuick) {
    final color = _isSignUp ? AppColors.neonBlue : AppColors.neonGreen;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.bgElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isQuick
                        ? Icons.flash_on
                        : (_isSignUp ? Icons.person_add : Icons.login),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    _isSignUp ? t.authSignUp : t.authSignIn,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _bonusCoinsRow(AppLocalizations t) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.neonYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(t.authBonusCoins,
                style: TextStyle(
                    color: AppColors.neonYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(AppLocalizations t) {
    if (_mode == _AuthMode.phone) return SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? t.authAlreadyAccount : t.authNoAccount,
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

  // ════════════════════════════════════════════════════════════
  // HANDLERS
  // ════════════════════════════════════════════════════════════
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final supabase = SupabaseService();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();
    final t = AppLocalizations.of(context)!;

    try {
      if (_mode == _AuthMode.quick) {
        // Quick account
        if (_isSignUp) {
          final (result, error) = await supabase.quickSignUp(username, password);
          if (error != null) {
            setState(() => _errorMessage = error);
          } else if (result != null) {
            await _updateUsernameAndPop(username, t.authAccountCreated);
          }
        } else {
          final (result, error) = await supabase.quickSignIn(username, password);
          if (error != null) {
            setState(() => _errorMessage = error);
          } else if (result != null) {
            _successAndPop(t.authLoginSuccess);
          }
        }
      } else {
        // Email mode
        final email = _emailController.text.trim();
        if (_isSignUp) {
          final (result, error) = await supabase.signUpWithEmail(email, password);
          if (error != null) {
            setState(() => _errorMessage = error);
          } else if (result != null) {
            if (username.isNotEmpty) {
              await _updateUsernameAndPop(username, t.authAccountCreated);
            } else {
              _successAndPop(t.authAccountCreated);
            }
          }
        } else {
          final (result, error) = await supabase.signInWithEmail(email, password);
          if (error != null) {
            setState(() => _errorMessage = error);
          } else if (result != null) {
            _successAndPop(t.authLoginSuccess);
          }
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erreur: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (result, error) = await SupabaseService().signInWithGoogle();
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    } else if (result != null) {
      _successAndPop(AppLocalizations.of(context)!.authLoginSuccess);
    } else {
      // User cancelled
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 8) {
      setState(() => _errorMessage = 'Numero invalide');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final error = await SupabaseService().sendPhoneOtp(phone);
    if (!mounted) return;

    setState(() => _isLoading = false);
    if (error != null) {
      setState(() => _errorMessage = error);
    } else {
      setState(() => _otpSent = true);
    }
  }

  Future<void> _handleVerifyOtp() async {
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 4) {
      setState(() => _errorMessage = 'Code invalide');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (result, error) =
        await SupabaseService().verifyPhoneOtp(phone, otp);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    } else if (result != null) {
      _successAndPop(AppLocalizations.of(context)!.authLoginSuccess);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    final t = AppLocalizations.of(context)!;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = t.authEnterEmailFirst);
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
          content: Text(t.authEmailResetSent(email)),
          backgroundColor: AppColors.neonGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _errorMessage = error);
    }
  }

  Future<void> _updateUsernameAndPop(String username, String msg) async {
    try {
      final ludo = context.read<LudoProvider>();
      await ludo.loadProfile();
      await ludo.updateUsername(username);
    } catch (_) {}
    _successAndPop(msg);
  }

  void _successAndPop(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(msg),
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
