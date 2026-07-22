// ============================================================
// Plugbet – Dialog de vérification OTP (SMS)
// ============================================================
// Partagé par l'inscription et la connexion par téléphone. Retourne
// true si le code a été vérifié avec succès.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'plugbet_wordmark.dart' show kPlugbetGreen;

Future<bool?> showPhoneOtpDialog(BuildContext context, String phone) {
  final supabase = SupabaseService();
  final otpCtrl = TextEditingController();
  var verifying = false;
  String? otpError;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text('Vérification',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Entre le code reçu par SMS au $phone',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, letterSpacing: 6),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: kPlugbetGreen),
                    ),
                  ),
                ),
                if (otpError != null) ...[
                  const SizedBox(height: 8),
                  Text(otpError!,
                      style: const TextStyle(
                          color: Color(0xFFE53935), fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    verifying ? null : () => Navigator.pop(dialogCtx, false),
                child: Text('Annuler',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPlugbetGreen,
                  foregroundColor: Colors.black,
                ),
                onPressed: verifying
                    ? null
                    : () async {
                        setLocal(() {
                          verifying = true;
                          otpError = null;
                        });
                        final (resp, e) = await supabase.verifyPhoneOtp(
                            phone, otpCtrl.text.trim());
                        if (resp != null && e == null) {
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx, true);
                          }
                        } else {
                          setLocal(() {
                            verifying = false;
                            otpError = e ?? 'Code invalide.';
                          });
                        }
                      },
                child: verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Vérifier'),
              ),
            ],
          );
        },
      );
    },
  );
}
