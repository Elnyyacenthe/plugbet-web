// ============================================================
// Plugbet – Page de connexion (redesign, cohérente avec l'inscription)
// ============================================================
// Deux méthodes de connexion — par téléphone (OTP SMS) ou par email —
// alignées sur les options de la page d'inscription, plus Google.
// (La méthode « en un clic » de l'inscription crée un compte anonyme
// non ré-authentifiable : elle n'a pas d'équivalent à la connexion.)
// Chrome sombre #0B1120, accents verts.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/countries.dart';
import '../widgets/plugbet_wordmark.dart' show kPlugbetGreen;
import '../widgets/google_logo.dart';
import '../widgets/country_picker.dart';
import '../widgets/phone_otp_dialog.dart';
import '../ludo/providers/ludo_provider.dart';
import 'signup_screen.dart';

enum _LoginMethod { phone, email }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _supabase = SupabaseService();

  _LoginMethod _method = _LoginMethod.phone;
  Country _country = defaultCountry();

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _fieldsValid {
    switch (_method) {
      case _LoginMethod.phone:
        return _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length >= 6;
      case _LoginMethod.email:
        // Accepte une adresse complete OU un pseudo de compte rapide.
        // Un pseudo n'a ni '@' ni '.', d'ou la validation en deux temps.
        final id = _emailCtrl.text.trim();
        if (_passwordCtrl.text.length < 6) return false;
        return id.contains('@') ? id.contains('.') : id.length >= 3;
    }
  }

  bool get _canSubmit => _fieldsValid && !_loading;

  // ── Handlers ─────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_canSubmit) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (_method) {
        case _LoginMethod.phone:
          await _loginPhone();
          break;
        case _LoginMethod.email:
          await _loginEmail();
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginPhone() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+${_country.dial}$digits';
    final err = await _supabase.sendPhoneOtp(phone);
    if (err != null) {
      _fail(err);
      return;
    }
    if (!mounted) return;
    final verified = await showPhoneOtpDialog(context, phone);
    if (verified == true) {
      await _success('Content de te revoir !');
    }
  }

  Future<void> _loginEmail() async {
    final input = _emailCtrl.text.trim();

    // Les comptes rapides (inscription pseudo + mot de passe) n'ont pas
    // d'adresse visible : elle est fabriquee en `pseudo@plugbet.app` et
    // n'est JAMAIS montree a l'utilisateur. Sans cette resolution, leur
    // porteur ne peut pas se reconnecter — il devrait deviner une
    // adresse qu'il n'a jamais vue.
    final email =
        input.contains('@') ? input : _supabase.quickEmailFor(input);

    final (resp, err) =
        await _supabase.signInWithEmail(email, _passwordCtrl.text);
    if (err != null) {
      _fail(err);
      return;
    }
    if (resp != null) {
      await _success('Content de te revoir !');
    }
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (resp, err) = await _supabase.signInWithGoogle();
      if (err != null) {
        _fail(err);
        return;
      }
      if (resp != null) {
        await _success('Connecté avec Google.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    // Un compte rapide n'a pas de vraie adresse : `pseudo@plugbet.app`
    // ne recoit aucun courrier, un lien de reinitialisation n'y
    // arriverait jamais. On le dit plutot que d'envoyer dans le vide.
    if (!email.contains('@')) {
      _fail('Entre ton adresse email. Un compte cree avec un simple '
          'pseudo ne recoit pas de courrier : contacte le support.');
      return;
    }
    await _supabase.sendPasswordResetEmail(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email de réinitialisation envoyé.')),
    );
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _success(String message) async {
    if (!mounted) return;
    try {
      await context.read<LudoProvider>().loadProfile();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: kPlugbetGreen),
    );
    Navigator.pop(context, true);
  }

  void _goToSignup() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  Future<void> _pickCountry() async {
    final selected = await showCountryPicker(context);
    if (selected != null) setState(() => _country = selected);
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Connexion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Content de te revoir sur Plugbet',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 22),

              _methodSelector(),
              const SizedBox(height: 20),

              ..._methodFields(),

              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],

              _loginButton(),
              const SizedBox(height: 18),

              _orSeparator(),
              const SizedBox(height: 18),

              _googleButton(),
              const SizedBox(height: 20),

              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _methodSelector() {
    return Row(
      children: [
        _methodButton(_LoginMethod.phone, Icons.phone_rounded, 'Téléphone'),
        const SizedBox(width: 10),
        _methodButton(
            _LoginMethod.email, Icons.mail_outline_rounded, 'Email / Pseudo'),
      ],
    );
  }

  Widget _methodButton(_LoginMethod m, IconData icon, String label) {
    final active = _method == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _method = m;
          _error = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 50,
          decoration: BoxDecoration(
            color: active ? kPlugbetGreen : AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: active ? kPlugbetGreen : AppColors.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: active ? Colors.white : AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _methodFields() {
    switch (_method) {
      case _LoginMethod.phone:
        return [
          _fieldLabel('Votre pays'),
          const SizedBox(height: 6),
          _countryField(),
          const SizedBox(height: 14),
          _fieldLabel('Numéro de téléphone'),
          const SizedBox(height: 6),
          _phoneField(),
          const SizedBox(height: 16),
        ];
      case _LoginMethod.email:
        return [
          _fieldLabel('Adresse email ou pseudo'),
          const SizedBox(height: 6),
          _emailField(),
          const SizedBox(height: 14),
          _fieldLabel('Mot de passe'),
          const SizedBox(height: 6),
          _passwordField(),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _forgotPassword,
              child: const Text(
                'Mot de passe oublié ?',
                style: TextStyle(
                    color: kPlugbetGreen,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ];
    }
  }

  Widget _countryField() {
    return GestureDetector(
      onTap: _pickCountry,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Text(_country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_country.name,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _phoneField() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text('+${_country.dial}',
              style: const TextStyle(
                  color: kPlugbetGreen, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: AppColors.divider),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '6 12 34 56 78',
                hintStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailField() {
    return _inputContainer(
      leading: Icon(Icons.mail_outline_rounded,
          color: AppColors.textMuted, size: 20),
      child: TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: 'exemple@email.com ou ton pseudo',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return _inputContainer(
      leading: Icon(Icons.lock_outline_rounded,
          color: AppColors.textMuted, size: 20),
      child: TextField(
        controller: _passwordCtrl,
        obscureText: _obscure,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: '••••••',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
      ),
      trailing: GestureDetector(
        onTap: () => setState(() => _obscure = !_obscure),
        child: Icon(
          _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: AppColors.textMuted,
          size: 20,
        ),
      ),
    );
  }

  Widget _inputContainer(
      {required Widget child, Widget? leading, Widget? trailing}) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
        ],
      ),
    );
  }

  Widget _loginButton() {
    final enabled = _canSubmit;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? _login : null,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF37DD86), Color(0xFF149E56)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: kPlugbetGreen.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : const Text(
                  'Se connecter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _orSeparator() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('ou', style: TextStyle(color: AppColors.textMuted)),
        ),
        Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
      ],
    );
  }

  Widget _googleButton() {
    return GestureDetector(
      onTap: _loading ? null : _google,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            GoogleLogo(size: 22),
            SizedBox(width: 10),
            Text(
              'Se connecter avec Google',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Center(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Pas encore de compte ? ',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
            TextSpan(
              text: 'Inscrivez-vous',
              style: const TextStyle(
                color: kPlugbetGreen,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
              recognizer: (TapGestureRecognizer()..onTap = _goToSignup),
            ),
          ],
        ),
      ),
    );
  }
}
