// ============================================================
// Plugbet — Jeu responsable
// ============================================================
// Limites de mise (jour / semaine), limite de perte quotidienne, et
// auto-exclusion. Branche sur les RPC serveur (source de verite) :
//   - rg_set_limits(p_daily_stake, p_weekly_stake, p_daily_loss, p_reality_check_minutes)
//   - rg_self_exclude(p_days)  -> ne peut qu'ETENDRE une exclusion existante
// Lecture des limites courantes via la table responsible_gaming_limits (RLS
// select own). Ces mecanismes sont appliques a la pose de pari cote serveur
// (assert_can_place_bet) et ne peuvent pas etre contournes par le 2Up.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/app_icons.dart';

class ResponsibleGamingScreen extends StatefulWidget {
  const ResponsibleGamingScreen({super.key});

  @override
  State<ResponsibleGamingScreen> createState() =>
      _ResponsibleGamingScreenState();
}

class _ResponsibleGamingScreenState extends State<ResponsibleGamingScreen> {
  final _dailyStake = TextEditingController();
  final _weeklyStake = TextEditingController();
  final _dailyLoss = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  DateTime? _selfExcludedUntil;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dailyStake.dispose();
    _weeklyStake.dispose();
    _dailyLoss.dispose();
    super.dispose();
  }

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('responsible_gaming_limits')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        _dailyStake.text = _fmt(row['daily_stake_limit']);
        _weeklyStake.text = _fmt(row['weekly_stake_limit']);
        _dailyLoss.text = _fmt(row['daily_loss_limit']);
        final until = row['self_excluded_until']?.toString();
        _selfExcludedUntil = until != null ? DateTime.tryParse(until) : null;
      }
    } catch (_) {/* silencieux : ecran reste utilisable */}
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(dynamic v) => (v == null) ? '' : v.toString();
  int? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('rg_set_limits', params: {
        'p_daily_stake': _parse(_dailyStake),
        'p_weekly_stake': _parse(_weeklyStake),
        'p_daily_loss': _parse(_dailyLoss),
        'p_reality_check_minutes': null,
      });
      if (!mounted) return;
      _snack('Limites enregistrées ✓', AppColors.primary);
    } catch (e) {
      if (!mounted) return;
      _snack('Erreur : $e', AppColors.neonRed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selfExclude(int days) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Auto-exclusion',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
        content: Text(
          'Tu ne pourras plus placer de pari pendant $days jours. '
          'Cette décision est irréversible avant la fin de la période.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await Supabase.instance.client
          .rpc('rg_self_exclude', params: {'p_days': days});
      if (!mounted) return;
      setState(() =>
          _selfExcludedUntil = DateTime.tryParse(res?.toString() ?? ''));
      _snack('Auto-exclusion activée', AppColors.neonOrange);
    } catch (e) {
      if (!mounted) return;
      _snack('Erreur : $e', AppColors.neonRed);
    }
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: c,
      content: Text(msg,
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.w800)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _selfExcludedUntil != null &&
        _selfExcludedUntil!.isAfter(DateTime.now());
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Jeu responsable',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                Row(children: [
                  Icon(AppIcons.verified, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Garde le contrôle de ton jeu. Ces limites sont appliquées à chaque pari et priment sur toute promotion (2Up compris).',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                _sectionTitle('Limites de mise'),
                _field(_dailyStake, 'Mise max par jour (FCFA)'),
                _field(_weeklyStake, 'Mise max par semaine (FCFA)'),
                _field(_dailyLoss, 'Perte max par jour (FCFA)'),
                const SizedBox(height: 6),
                Text('Laisse un champ vide pour aucune limite.',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11.5)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '...' : 'ENREGISTRER',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 30),
                _sectionTitle('Auto-exclusion'),
                if (excluded) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.neonOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.neonOrange.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'Tu es auto-exclu jusqu\'au ${_dateStr(_selfExcludedUntil!)}. '
                      'Les paris sont bloqués jusque-là.',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Suspends ton compte de paris pour une durée choisie. '
                    'Impossible de revenir en arrière avant la fin.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _exclBtn('7 jours', 7),
                    const SizedBox(width: 10),
                    _exclBtn('30 jours', 30),
                    const SizedBox(width: 10),
                    _exclBtn('90 jours', 90),
                  ]),
                ],
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8)),
      );

  Widget _field(TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.bgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      );

  Widget _exclBtn(String label, int days) => Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.neonRed,
            side: BorderSide(color: AppColors.neonRed.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => _selfExclude(days),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      );

  String _dateStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
