// ============================================================
// Plugbet — Ecran "Mes bonus" : liste des codes bonus (vouchers)
// ============================================================
// Affiche tous les codes bonus gagnes via les promotions. Chaque code actif
// est copiable au clic et utilisable UNE SEULE FOIS sur un coupon (champ
// "Code bonus" de la feuille de pari).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/bonus_service.dart';

class BonusCodesScreen extends StatefulWidget {
  const BonusCodesScreen({super.key});

  @override
  State<BonusCodesScreen> createState() => _BonusCodesScreenState();
}

class _BonusCodesScreenState extends State<BonusCodesScreen> {
  static const _gold = Color(0xFFFFB020);
  final _service = BonusService();
  List<BonusCode> _codes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final codes = await _service.getMyBonusCodes();
    if (!mounted) return;
    setState(() {
      _codes = codes;
      _loading = false;
    });
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code $code copié'),
        backgroundColor: AppColors.neonGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _codes.where((c) => c.isActive).toList();
    final totalActive = active.fold<int>(0, (s, c) => s + c.amount);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: Text('Mes bonus',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _gold,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _headerCard(active.length, totalActive),
                  const SizedBox(height: 16),
                  if (_codes.isEmpty)
                    _emptyState()
                  else
                    ..._codes.map(_codeCard),
                ],
              ),
      ),
    );
  }

  Widget _headerCard(int activeCount, int totalActive) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_gold.withValues(alpha: 0.18), _gold.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.card_giftcard_rounded, color: _gold, size: 22),
            const SizedBox(width: 10),
            Text('$activeCount bonus actif${activeCount > 1 ? 's' : ''}',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('$totalActive FCFA',
                style: TextStyle(
                    color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Copie un code et colle-le dans le champ « Code bonus » de ton coupon '
            'pour financer ta mise. Chaque code est utilisable une seule fois.',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.card_giftcard_outlined,
              color: AppColors.textMuted, size: 48),
          const SizedBox(height: 14),
          Text('Aucun bonus pour le moment',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Gagne des bonus avec PlugSafe, PlugShield et PlugBoost en pariant. '
            'Ils apparaîtront ici sous forme de codes à utiliser sur tes coupons.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(BonusCode c) {
    final active = c.isActive;
    final accent = active ? _gold : AppColors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? _gold.withValues(alpha: 0.4)
              : AppColors.divider.withValues(alpha: 0.5),
          width: active ? 1 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(c.sourceLabel.toUpperCase(),
                  style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ),
            const Spacer(),
            Text('${c.amount} FCFA',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          Text(c.originText,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          const SizedBox(height: 12),
          if (active)
            InkWell(
              onTap: () => _copy(c.code),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(c.code,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        )),
                  ),
                  Icon(Icons.copy_rounded, color: _gold, size: 20),
                  const SizedBox(width: 4),
                  Text('COPIER',
                      style: TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ]),
              ),
            )
          else
            Row(children: [
              Icon(
                  c.status == 'used'
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 15,
                  color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                  c.status == 'used'
                      ? 'Déjà utilisé sur un coupon'
                      : 'Expiré',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(c.code,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.lineThrough,
                  )),
            ]),
        ],
      ),
    );
  }
}
