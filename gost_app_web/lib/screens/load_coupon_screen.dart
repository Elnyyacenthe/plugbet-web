// ============================================================
// LoadCouponScreen — Charger un ticket par son code court
// ============================================================
// Permet a un joueur de :
//   - Coller le code court (8 chars) d'un coupon partagé
//   - Voir le ticket complet (style 1xBet)
//   - Le dupliquer dans son panier
//
// RPC : lookup_bet_by_code (public, retourne donnees anonymisees)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_theme.dart';
import 'bet_ticket_detail_screen.dart';

class LoadCouponScreen extends StatefulWidget {
  const LoadCouponScreen({super.key});

  @override
  State<LoadCouponScreen> createState() => _LoadCouponScreenState();
}

class _LoadCouponScreenState extends State<LoadCouponScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCoupon() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Le code doit faire au moins 6 caractères.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc('lookup_bet_by_code', params: {'p_code': code});
      if (!mounted) return;
      if (res is! Map || res['found'] != true) {
        setState(() {
          _loading = false;
          _error = 'Aucun ticket trouvé pour le code "$code". '
              'Vérifie le code et réessaie.';
        });
        return;
      }
      setState(() => _loading = false);
      // Ouvre le ticket en mode "partagé" (réutilise BetTicketDetailScreen)
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BetTicketDetailScreen(
          bet: Map<String, dynamic>.from(res),
          // Pas de liveById ici (utilisateur arrive via partage)
        ),
      ));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _humanizeError(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erreur réseau. Vérifie ta connexion.';
      });
    }
  }

  String _humanizeError(String raw) {
    if (raw.contains('LOOKUP_BET_CODE_TOO_SHORT')) {
      return 'Le code doit faire au moins 6 caractères.';
    }
    if (raw.contains('LOOKUP_BET_CODE_INVALID')) {
      return 'Format de code invalide (hex uniquement : 0-9, A-F).';
    }
    if (raw.contains('LOOKUP_BET_AUTH_REQUIRED')) {
      return 'Tu dois être connecté pour charger un coupon.';
    }
    return 'Erreur : $raw';
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    setState(() {
      _codeCtrl.text = text.replaceAll('#', '').trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: const ReliefAppBar(title: 'Charger un coupon'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bandeau infos
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.neonBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.neonBlue.withValues(alpha: 0.3),
                      width: 0.6),
                ),
                child: Row(children: [
                  Icon(AppIcons.qrCode,
                      size: 22, color: AppColors.neonBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Code de coupon',
                            style: TextStyle(
                              color: AppColors.neonBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                            'Colle ici le code partagé par un autre joueur '
                            'pour voir son ticket et le dupliquer.',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.3)),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              // Champ input avec bouton Coller
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.divider.withValues(alpha: 0.5),
                      width: 0.5),
                ),
                child: Row(children: [
                  const SizedBox(width: 14),
                  Icon(AppIcons.tag,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      autofocus: true,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F#\-]')),
                        LengthLimitingTextInputFormatter(40),
                      ],
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _loadCoupon(),
                      decoration: InputDecoration(
                        hintText: 'BC9B7030',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.6),
                          fontSize: 16,
                          letterSpacing: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(AppIcons.paste,
                        size: 18, color: AppColors.neonBlue),
                    tooltip: 'Coller',
                    onPressed: _pasteFromClipboard,
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(AppIcons.warning,
                        size: 14, color: AppColors.neonRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                            color: AppColors.neonRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: _loading
                    ? Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primaryInk),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _loadCoupon,
                        icon: const Icon(AppIcons.search, size: 18),
                        label: const Text('Charger le ticket',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 0.3)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
              ),
              const Spacer(),
              // Astuce
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(AppIcons.idea,
                      size: 16, color: AppColors.neonYellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Astuce : tu peux partager ton propre code de coupon '
                        'depuis l\'écran "Détails du pari" en faisant un '
                        'appui long sur le numéro.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
