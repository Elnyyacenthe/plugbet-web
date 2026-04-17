// ============================================================
// FANTASY MODULE – Écran connexion Entry ID
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers/fpl_provider.dart';

class FantasyConnectScreen extends StatefulWidget {
  const FantasyConnectScreen({super.key});

  @override
  State<FantasyConnectScreen> createState() => _FantasyConnectScreenState();
}

class _FantasyConnectScreenState extends State<FantasyConnectScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final id = int.tryParse(_ctrl.text.trim());
    if (id == null) {
      setState(() => _error = 'Entrez un ID valide (ex: 1234567)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<FplProvider>().connectEntry(id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _error = 'ID introuvable. Vérifiez votre Entry ID FPL.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.fantasyConnectTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: AppColors.neonGreen, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.fantasyEntryIdHelp,
                        style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w700)),
                  ]),
                  SizedBox(height: 10),
                  Text(
                    '1. Connectez-vous sur fantasy.premierleague.com\n'
                    '2. Allez dans "Points" ou "Transfers"\n'
                    '3. Votre Entry ID est visible dans l\'URL :\n'
                    '   /entry/XXXXXXX/event/...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),
            Text(AppLocalizations.of(context)!.fantasyEntryIdLabel,
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'ex: 1234567',
                hintStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.bgCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.neonGreen, width: 2),
                ),
                errorText: _error,
                errorStyle: TextStyle(color: AppColors.neonRed),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonGreen,
                  foregroundColor: AppColors.bgDark,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bgDark))
                    : Text(AppLocalizations.of(context)!.fantasyConnect, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            SizedBox(height: 16),
            Consumer<FplProvider>(
              builder: (_, fpl, __) {
                if (fpl.entryId == null) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () {
                    fpl.disconnectEntry();
                    Navigator.pop(context);
                  },
                  child: Text(AppLocalizations.of(context)!.fantasyDisconnect,
                      style: TextStyle(color: AppColors.neonRed)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
