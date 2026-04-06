// ============================================================
// Plugbet – Paramètres complets
// 7 sections : Audio, Visuel, Gameplay, Notifs, Compte, Accessibilité, Infos
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/hive_service.dart';
import '../ludo/services/audio_service.dart';
import '../providers/theme_provider.dart';
import 'support_screen.dart';

class SettingsScreen extends StatefulWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;

  const SettingsScreen({
    super.key,
    required this.hiveService,
    required this.supabaseService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Audio ──────────────────────────────────────────────────
  late bool _soundEnabled;
  late double _sfxVolume;
  late double _musicVolume;

  // ── Gameplay ────────────────────────────────────────────────
  late String _aiDifficulty;

  // ── Notifications & Social ──────────────────────────────────
  late bool _notificationsEnabled;
  late bool _goalAlerts;
  late bool _matchStartAlerts;
  late bool _notifSounds;
  late bool _vibrationEnabled;
  late bool _vibrationOnEvents;
  late bool _inGameChat;
  late bool _autoInvite;

  // ── Accessibilité ───────────────────────────────────────────
  late bool _leftyMode;
  late bool _highContrast;
  late bool _largeText;

  HiveService get _h => widget.hiveService;

  bool _b(String key, bool def) => _h.getSetting<bool>(key) ?? def;
  double _d(String key, double def) => (_h.getSetting<double>(key) ?? def).clamp(0.0, 1.0);
  String _s(String key, String def) => _h.getSetting<String>(key) ?? def;

  @override
  void initState() {
    super.initState();
    _soundEnabled  = _b('sound_enabled', true);
    _sfxVolume     = _d('sfx_volume', 0.8);
    _musicVolume   = _d('music_volume', 0.5);
    _aiDifficulty  = _s('ai_difficulty', 'Moyen');
    _notificationsEnabled = _b('notifications', true);
    _goalAlerts           = _b('goal_alerts', true);
    _matchStartAlerts     = _b('match_start_alerts', true);
    _notifSounds          = _b('notif_sounds', true);
    _vibrationEnabled     = _b('game_vibration', true);
    _vibrationOnEvents    = _b('vibration_events', true);
    _inGameChat           = _b('in_game_chat', true);
    _autoInvite           = _b('auto_invite', false);
    _leftyMode    = _b('lefty_mode', false);
    _highContrast = _b('high_contrast', false);
    _largeText    = _b('large_text', false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _save(String key, dynamic val) => _h.saveSetting(key, val);

  void _showInfoDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(body, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _openSupportScreen() {
    debugPrint('[SUPPORT] bouton tapé');
    try {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
      debugPrint('[SUPPORT] Navigator.push appelé');
    } catch (e, st) {
      debugPrint('[SUPPORT] ERREUR: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 8)),
      );
    }
  }

  // ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
            children: [
              // ── Titre ─────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 20),
                child: Text('Paramètres',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -1)),
              ),

              // ══════════════════════════════════════════════
              // 1. AUDIO
              // ══════════════════════════════════════════════
              _sectionHeader('Audio', Icons.volume_up, AppColors.neonBlue),
              _card(Column(children: [
                _switchRow('Sons activés', 'Activer ou couper tous les sons',
                    _soundEnabled, (v) => setState(() {
                  _soundEnabled = v;
                  _save('sound_enabled', v);
                  AudioService.instance.toggleSound(v);
                })),
                if (_soundEnabled) ...[
                  const _Divider(),
                  _sliderRow('Volume effets sonores', _sfxVolume, (v) => setState(() {
                    _sfxVolume = v;
                    _save('sfx_volume', v);
                    AudioService.instance.reloadSettings();
                  })),
                  const _Divider(),
                  _sliderRow('Volume musique de fond', _musicVolume, (v) => setState(() {
                    _musicVolume = v;
                    _save('music_volume', v);
                    AudioService.instance.reloadSettings();
                  })),
                ],
              ])),

              SizedBox(height: 20),

              // ══════════════════════════════════════════════
              // 2. THÈME
              // ══════════════════════════════════════════════
              _sectionHeader('Apparence', Icons.palette, AppColors.neonYellow),
              _card(Column(children: [
                Builder(builder: (ctx) {
                  final tp = ctx.watch<ThemeProvider>();
                  return _switchRow(
                    'Mode clair',
                    'Basculer entre le thème sombre et clair',
                    !tp.isDark,
                    (v) => tp.toggle(),
                  );
                }),
              ])),

              SizedBox(height: 20),

              // ══════════════════════════════════════════════
              // 3. GAMEPLAY
              // ══════════════════════════════════════════════
              _sectionHeader('Gameplay', Icons.sports_esports, AppColors.neonGreen),
              _card(Column(children: [
                _dropdownRow('Difficulté IA', 'Checkers & Solitaire',
                    ['Facile', 'Moyen', 'Difficile'], _aiDifficulty,
                    (v) => setState(() { _aiDifficulty = v; _save('ai_difficulty', v); })),
              ])),

              SizedBox(height: 20),

              // ══════════════════════════════════════════════
              // 4. NOTIFICATIONS & SOCIAL
              // ══════════════════════════════════════════════
              _sectionHeader('Notifications & Social', Icons.notifications, AppColors.neonOrange),
              _card(Column(children: [
                _switchRow('Notifications push', 'Invites, tour à jouer, victoire d\'ami',
                    _notificationsEnabled, (v) => setState(() {
                  _notificationsEnabled = v; _save('notifications', v);
                })),
                if (_notificationsEnabled) ...[
                  const _Divider(),
                  _switchRow('Sons de notification', '', _notifSounds,
                      (v) => setState(() { _notifSounds = v; _save('notif_sounds', v); }), indent: true),
                  const _Divider(),
                  _switchRow('Alertes buts', 'Pour vos équipes favorites', _goalAlerts,
                      (v) => setState(() { _goalAlerts = v; _save('goal_alerts', v); }), indent: true),
                  const _Divider(),
                  _switchRow('Début de match', 'Coup d\'envoi de vos favoris', _matchStartAlerts,
                      (v) => setState(() { _matchStartAlerts = v; _save('match_start_alerts', v); }), indent: true),
                ],
                const _Divider(),
                _switchRow('Vibrations', 'Retour haptique global',
                    _vibrationEnabled, (v) => setState(() { _vibrationEnabled = v; _save('game_vibration', v); })),
                if (_vibrationEnabled) ...[
                  const _Divider(),
                  _switchRow('Vibrations sur événements', 'Dé, capture, Cora, victoire',
                      _vibrationOnEvents, (v) => setState(() { _vibrationOnEvents = v; _save('vibration_events', v); }), indent: true),
                ],
                const _Divider(),
                _switchRow('Chat en jeu', 'Messagerie pendant les parties multijoueur',
                    _inGameChat, (v) => setState(() { _inGameChat = v; _save('in_game_chat', v); })),
                const _Divider(),
                _switchRow('Invites automatiques', 'Proposer amis pour rejoindre la partie',
                    _autoInvite, (v) => setState(() { _autoInvite = v; _save('auto_invite', v); })),
              ])),

              SizedBox(height: 20),

              // ══════════════════════════════════════════════
              // 6. ACCESSIBILITÉ & CONFORT
              // ══════════════════════════════════════════════
              _sectionHeader('Accessibilité & Confort', Icons.accessibility, AppColors.neonGreen),
              _card(Column(children: [
                _switchRow('Mode gaucher', 'Inverser les commandes de glissement',
                    _leftyMode, (v) => setState(() { _leftyMode = v; _save('lefty_mode', v); })),
                const _Divider(),
                _switchRow('Contraste élevé', 'Meilleure lisibilité pour malvoyants',
                    _highContrast, (v) => setState(() {
                  _highContrast = v; _save('high_contrast', v);
                  context.read<ThemeProvider>().notifyAccessibilityChanged();
                })),
                const _Divider(),
                _switchRow('Texte agrandi', 'Augmenter la taille du texte dans les menus',
                    _largeText, (v) => setState(() {
                  _largeText = v; _save('large_text', v);
                  context.read<ThemeProvider>().notifyAccessibilityChanged();
                })),
              ])),

              SizedBox(height: 20),

              // ══════════════════════════════════════════════
              // 7. INFOS & SUPPORT
              // ══════════════════════════════════════════════
              _sectionHeader('Infos & Support', Icons.info_outline, AppColors.textMuted),
              _card(Column(children: [
                _infoRow('Application', 'Plugbet'),
                const _Divider(),
                _infoRow('Version', '1.0.0'),
                const _Divider(),
                _linkRow('Règles des jeux', Icons.rule, () => _showInfoDialog(
                  'Règles des jeux',
                  '• Ludo : Lancez le dé, déplacez vos 4 pions. '
                  'Un 6 permet de sortir un pion et de rejouer. '
                  'Premier à ramener tous ses pions gagne.\n\n'
                  '• Cora Dice : Lancez les dés à tour de rôle. '
                  'Évitez les 7 (pénalité). Celui avec le plus de points gagne.\n\n'
                  '• Dames : Capturez tous les pions adverses ou bloquez-les. '
                  'Un pion atteint le bout du plateau pour devenir dame.\n\n'
                  '• Solitaire : Retirez les pions en sautant par-dessus. '
                  'Objectif : n\'en laisser qu\'un seul.\n\n'
                  '• Aviator : Misez avant le décollage, encaissez avant le crash. '
                  'Plus le multiplicateur est haut, plus le gain est gros.',
                )),
                const _Divider(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSupportScreen,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(children: [
                      Icon(Icons.support_agent, size: 18, color: AppColors.neonGreen),
                      SizedBox(width: 12),
                      Expanded(child: Text('Nous contacter / Support',
                          style: TextStyle(fontSize: 14, color: AppColors.neonGreen, fontWeight: FontWeight.w600))),
                      Icon(Icons.chevron_right, size: 18, color: AppColors.neonGreen),
                    ]),
                  ),
                ),
                const _Divider(),
                _linkRow('Politique de confidentialité', Icons.privacy_tip_outlined, () => _showInfoDialog(
                  'Politique de confidentialité',
                  'Plugbet respecte votre vie privée.\n\n'
                  '• Données collectées : identifiant anonyme, nom d\'utilisateur choisi, '
                  'statistiques de jeu et solde de coins.\n\n'
                  '• Utilisation : améliorer l\'expérience de jeu, classements et matchmaking.\n\n'
                  '• Partage : aucune donnée personnelle n\'est vendue ni partagée avec des tiers.\n\n'
                  '• Suppression : vous pouvez demander la suppression de votre compte '
                  'via l\'option Support dans les paramètres.\n\n'
                  'Contact : support@plugbet.app',
                )),
                const _Divider(),
                _linkRow('Conditions d\'utilisation', Icons.description_outlined, () => _showInfoDialog(
                  'Conditions d\'utilisation',
                  '1. En utilisant Plugbet, vous acceptez ces conditions.\n\n'
                  '2. Les coins sont une monnaie virtuelle sans valeur réelle. '
                  'Aucun échange contre de l\'argent réel n\'est possible.\n\n'
                  '3. Tout comportement abusif (triche, multi-comptes, exploitation de bugs) '
                  'peut entraîner la suspension du compte.\n\n'
                  '4. Plugbet se réserve le droit de modifier les règles, les gains '
                  'et les fonctionnalités à tout moment.\n\n'
                  '5. L\'application est fournie « en l\'état » sans garantie.\n\n'
                  '6. Pour toute question, contactez-nous via le Support.',
                )),
              ])),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // WIDGETS HELPERS
  // ────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: EdgeInsets.only(left: 2, bottom: 8),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 8),
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 1.2)),
      ]),
    );
  }

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: child,
    );
  }

  Widget _switchRow(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged, {bool dense = false, bool indent = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 28 : 16, dense ? 6 : 10, 16, dense ? 6 : 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: dense ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: indent ? AppColors.textSecondary : AppColors.textPrimary)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.neonGreen,
          activeTrackColor: AppColors.neonGreen.withValues(alpha: 0.3),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }

  Widget _sliderRow(String title, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          Text('${(value * 100).round()} %',
              style: TextStyle(fontSize: 13, color: AppColors.neonGreen,
                  fontWeight: FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.neonGreen,
            inactiveTrackColor: AppColors.divider,
            thumbColor: AppColors.neonGreen,
            overlayColor: AppColors.neonGreen.withValues(alpha: 0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            trackHeight: 3,
          ),
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
        ),
      ]),
    );
  }



  Widget _dropdownRow(String title, String subtitle, List<String> items, String value,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        DropdownButton<String>(
          value: value,
          dropdownColor: AppColors.bgCard,
          underline: SizedBox(),
          style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w700, fontSize: 13),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
      ]),
    );
  }

  Widget _linkRow(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ]),
      ),
    );
  }

}

// ────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16);
}
