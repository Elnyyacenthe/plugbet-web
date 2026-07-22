// ============================================================
// Plugbet – Page d'inscription (redesign)
// ============================================================
// Trois méthodes : inscription en un clic (compte rapide), par numéro
// de téléphone (OTP SMS) ou par email. Le pays est partagé entre les
// méthodes et détermine la devise (non modifiable). L'utilisateur doit
// accepter les CGU, la politique de confidentialité et confirmer avoir
// au moins 21 ans avant de pouvoir s'inscrire. Chrome sombre #0B1120,
// accents verts.
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../utils/countries.dart';
import '../theme/app_theme.dart';
import '../widgets/plugbet_wordmark.dart' show kPlugbetGreen;
import '../widgets/google_logo.dart';
import '../widgets/country_picker.dart';
import '../widgets/phone_otp_dialog.dart';
import '../ludo/providers/ludo_provider.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../services/hive_service.dart';
import 'login_screen.dart';

enum _Method { oneClick, phone, email }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _supabase = SupabaseService();

  _Method _method = _Method.oneClick;
  Country _country = defaultCountry();

  final _promoCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _acceptTerms = false;
  bool _acceptPrivacy = false;
  bool _accept21 = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _promoCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _fieldsValid {
    switch (_method) {
      case _Method.oneClick:
        return true;
      case _Method.phone:
        final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
        return digits.length >= 6;
      case _Method.email:
        final e = _emailCtrl.text.trim();
        return e.contains('@') && e.contains('.') &&
            _passwordCtrl.text.length >= 6;
    }
  }

  bool get _canSubmit =>
      _acceptTerms && _acceptPrivacy && _accept21 && _fieldsValid && !_loading;

  // ── Handlers ─────────────────────────────────────────────────

  Future<void> _register() async {
    if (!_canSubmit) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (_method) {
        case _Method.oneClick:
          await _registerOneClick();
          break;
        case _Method.phone:
          await _registerPhone();
          break;
        case _Method.email:
          await _registerEmail();
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(14, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _registerOneClick() async {
    final r = Random.secure();
    final username =
        'Player${DateTime.now().millisecondsSinceEpoch % 1000000}${r.nextInt(999)}';
    final password = _randomPassword();
    final (resp, err) = await _supabase.quickSignUp(username, password);
    if (err != null) {
      _fail(err);
      return;
    }
    if (resp != null) {
      final (_, signInErr) = await _supabase.quickSignIn(username, password);
      if (signInErr != null) {
        _fail(signInErr);
        return;
      }
      // Compte 1 clic : on montre les identifiants generes (copiables) car
      // ils ne sont visibles nulle part ailleurs. L'utilisateur pourra les
      // modifier a tout moment dans son profil.
      if (mounted) {
        await _showCredentialsDialog(username, password);
      }
      await _success('Compte créé ! Bienvenue sur Plugbet.');
    }
  }

  /// Affiche les identifiants du compte rapide (pseudo + mot de passe),
  /// copiables individuellement ou ensemble. Non fermable en tapant a cote
  /// pour eviter que l'utilisateur les rate.
  Future<void> _showCredentialsDialog(String username, String password) async {
    Widget credRow(BuildContext ctx, String label, String value) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11.5)),
                  const SizedBox(height: 3),
                  SelectableText(
                    value,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copier',
              icon: const Icon(Icons.copy_rounded,
                  color: kPlugbetGreen, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('$label copié'),
                    backgroundColor: kPlugbetGreen,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.vpn_key_rounded, color: kPlugbetGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Tes identifiants',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB020).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFB020).withValues(alpha: 0.4)),
              ),
              child: const Text(
                'Note bien ces identifiants : ce sont tes accès pour te '
                'reconnecter. Tu pourras les modifier à tout moment dans ton profil.',
                style: TextStyle(
                    color: Color(0xFFFFD27A), fontSize: 12.5, height: 1.35),
              ),
            ),
            credRow(ctx, "Nom d'utilisateur", username),
            credRow(ctx, 'Mot de passe', password),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                  text: 'Pseudo : $username\nMot de passe : $password'));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('Identifiants copiés'),
                  backgroundColor: kPlugbetGreen,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.copy_all_rounded,
                color: kPlugbetGreen, size: 18),
            label: const Text('Tout copier',
                style: TextStyle(
                    color: kPlugbetGreen, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPlugbetGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("J'ai bien noté",
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _registerEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    var username = _usernameFromEmail(email);

    var res = await _supabase.signUpWithEmailAndUsername(email, password, username);
    if (res.status == SignUpStatus.usernameTaken) {
      // Réessaye une fois avec un suffixe aléatoire.
      username = '$username${Random.secure().nextInt(9999)}';
      res = await _supabase.signUpWithEmailAndUsername(email, password, username);
    }
    if (res.status == SignUpStatus.emailExists) {
      _fail('Un compte existe déjà avec cet email. Connecte-toi.');
      return;
    }
    if (res.status != SignUpStatus.success) {
      _fail(res.message ?? 'Inscription impossible.');
      return;
    }
    final (_, signInErr) = await _supabase.signInWithEmail(email, password);
    if (signInErr != null) {
      _fail(signInErr);
      return;
    }
    await _success('Compte créé ! Bienvenue sur Plugbet.');
  }

  String _usernameFromEmail(String email) {
    var base = email.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    if (base.length < 3) base = 'Player$base';
    if (base.length > 20) base = base.substring(0, 20);
    return base;
  }

  Future<void> _registerPhone() async {
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
      await _success('Compte créé ! Bienvenue sur Plugbet.');
    }
  }

  Future<void> _googleSignup() async {
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

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _success(String message) async {
    if (!mounted) return;
    // Message de bienvenue emouvant (feed in-app + notification OS).
    _sendWelcomeNotification();
    // Capture des references dependantes du context AVANT tout await
    // (evite l'usage de context a travers un async gap).
    final ludo = context.read<LudoProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // On proposera la recharge du compte a l'arrivee sur l'accueil.
    try {
      await HiveService().saveSetting('pending_recharge_prompt', true);
    } catch (_) {}
    // Rafraîchit le profil en mémoire (best-effort).
    try {
      await ludo.loadProfile();
    } catch (_) {}
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: kPlugbetGreen,
      ),
    );
    Navigator.pop(context, true);
  }

  /// Souhaite la bienvenue au nouveau joueur : une notification chaleureuse
  /// qui atterrit dans le feed in-app ET dans la barre de notifications.
  void _sendWelcomeNotification() {
    const title = 'Bienvenue dans la famille Plugbet 💚';
    const body =
        "Ton aventure commence maintenant. On est vraiment heureux de "
        "t'accueillir parmi nous. Que chaque pari t'apporte frisson et "
        "bonheur — on croit en toi. Bonne chance ! 🍀";
    try {
      context.read<NotificationProvider>().add(
            title: title,
            body: body,
            icon: Icons.celebration_rounded,
            color: kPlugbetGreen,
          );
    } catch (_) {/* provider absent : on ignore */}
    NotificationService.instance.showPushNotification(
      title: title,
      body: body,
      payload: 'welcome',
    );
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _pickCountry() async {
    final selected = await showCountryPicker(context);
    if (selected != null) setState(() => _country = selected);
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cur = currencyForCountry(_country.code);

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
                'Inscription Rapide',
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
                'Créez votre compte en quelques secondes',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 22),

              _methodSelector(),
              const SizedBox(height: 20),

              _fieldLabel('Votre pays'),
              const SizedBox(height: 6),
              _countryField(),
              const SizedBox(height: 16),

              _fieldLabel('Devise'),
              const SizedBox(height: 6),
              _currencyField(cur),
              const SizedBox(height: 16),

              // Champs spécifiques à la méthode.
              ..._methodFields(),

              _fieldLabel('Code promo (optionnel)'),
              const SizedBox(height: 6),
              _promoField(),
              const SizedBox(height: 18),

              _consentBlock(),
              const SizedBox(height: 12),

              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFFF6B6B), fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],

              _registerButton(),
              const SizedBox(height: 16),

              _infoBanner(),
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
        _methodButton(_Method.oneClick, Icons.bolt_rounded),
        const SizedBox(width: 10),
        _methodButton(_Method.phone, Icons.phone_rounded),
        const SizedBox(width: 10),
        _methodButton(_Method.email, Icons.mail_outline_rounded),
      ],
    );
  }

  Widget _methodButton(_Method m, IconData icon) {
    final active = _method == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _method = m;
          _error = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            color: active ? kPlugbetGreen : AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: active ? kPlugbetGreen : AppColors.divider),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: kPlugbetGreen.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: active ? Colors.white : AppColors.textMuted,
            size: 24,
          ),
        ),
      ),
    );
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
              child: Text(
                _country.name,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _currencyField(CurrencyInfo cur) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${cur.name} (${cur.iso})',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                ),
              ),
              Text(
                cur.iso,
                style: const TextStyle(
                  color: kPlugbetGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'Définie par ton pays — non modifiable.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  List<Widget> _methodFields() {
    switch (_method) {
      case _Method.oneClick:
        return const [
          _OneClickNote(),
          SizedBox(height: 16),
        ];
      case _Method.phone:
        return [
          _fieldLabel('Numéro de téléphone'),
          const SizedBox(height: 6),
          _phoneField(),
          const SizedBox(height: 16),
        ];
      case _Method.email:
        return [
          _fieldLabel('Adresse email'),
          const SizedBox(height: 6),
          _emailField(),
          const SizedBox(height: 14),
          _fieldLabel('Mot de passe'),
          const SizedBox(height: 6),
          _passwordField(),
          const SizedBox(height: 16),
        ];
    }
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
      child: TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: 'exemple@email.com',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
      ),
      leading: Icon(Icons.mail_outline_rounded,
          color: AppColors.textMuted, size: 20),
    );
  }

  Widget _passwordField() {
    return _inputContainer(
      leading:
          Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 20),
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

  Widget _promoField() {
    return _inputContainer(
      leading:
          Icon(Icons.groups_outlined, color: AppColors.textMuted, size: 20),
      child: TextField(
        controller: _promoCtrl,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: 'CODE123',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _inputContainer({required Widget child, Widget? leading, Widget? trailing}) {
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

  Widget _consentBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _checkRow(
            value: _acceptTerms,
            onChanged: (v) => setState(() => _acceptTerms = v),
            prefix: "J'accepte les ",
            link: 'Règles et conditions',
          ),
          _checkRow(
            value: _acceptPrivacy,
            onChanged: (v) => setState(() => _acceptPrivacy = v),
            prefix: "J'accepte la ",
            link: 'Politique de confidentialité',
          ),
          _checkRow(
            value: _accept21,
            onChanged: (v) => setState(() => _accept21 = v),
            prefix: "J'accepte et je confirme avoir au moins ",
            link: '21 ans',
          ),
        ],
      ),
    );
  }

  Widget _checkRow({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String prefix,
    required String link,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: value ? kPlugbetGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: value ? kPlugbetGreen : AppColors.textMuted, width: 1.6),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: prefix,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          height: 1.35),
                    ),
                    TextSpan(
                      text: link,
                      style: const TextStyle(
                        color: kPlugbetGreen,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor: kPlugbetGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registerButton() {
    final enabled = _canSubmit;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? _register : null,
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
                  "S'inscrire maintenant",
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

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kPlugbetGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPlugbetGreen.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Vous pourrez compléter votre profil après l\'inscription',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Color(0xFF7DEBAE), fontSize: 12.5, fontWeight: FontWeight.w600),
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
      onTap: _loading ? null : _googleSignup,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GoogleLogo(size: 22),
            const SizedBox(width: 10),
            const Text(
              "S'inscrire avec Google",
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
              text: 'Vous avez déjà un compte ? ',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
            ),
            TextSpan(
              text: 'Connectez-vous',
              style: const TextStyle(
                color: kPlugbetGreen,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
              recognizer: (TapGestureRecognizer()..onTap = _goToLogin),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneClickNote extends StatelessWidget {
  const _OneClickNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: kPlugbetGreen, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Un compte instantané sera créé. Aucun email ni numéro requis.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
