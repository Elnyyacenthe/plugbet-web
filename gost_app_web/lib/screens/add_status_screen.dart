// ============================================================
// AddStatusScreen — Creer un statut image (24h)
// ============================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/messaging_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class AddStatusScreen extends StatefulWidget {
  final File imageFile;
  const AddStatusScreen({super.key, required this.imageFile});

  /// Helper : ouvre le picker puis navigue vers ce screen
  static Future<bool> pickAndOpen(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked == null || !context.mounted) return false;
    return await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => AddStatusScreen(imageFile: File(picked.path)),
          ),
        ) ??
        false;
  }

  @override
  State<AddStatusScreen> createState() => _AddStatusScreenState();
}

class _AddStatusScreenState extends State<AddStatusScreen> {
  final _captionCtrl = TextEditingController();
  final _service = MessagingService();
  bool _sending = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);

    final status = await _service.createImageStatus(
      widget.imageFile,
      caption: _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (status != null) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.statusSendFailed),
          backgroundColor: AppColors.neonRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Nouveau statut',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Image plein cadre
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: Image.file(
                widget.imageFile,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Zone caption + envoyer
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              10,
              12,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            decoration: const BoxDecoration(color: Color(0xFF111111)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    child: TextField(
                      controller: _captionCtrl,
                      enabled: !_sending,
                      maxLines: null,
                      minLines: 1,
                      maxLength: 200,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                      cursorColor: AppColors.neonGreen,
                      decoration: const InputDecoration(
                        hintText: 'Ajouter une legende...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        counterText: '',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sending ? null : _submit,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.neonGreen,
                          AppColors.neonGreen.withValues(alpha: 0.7),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonGreen.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: _sending
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.black, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
