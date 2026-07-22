// ============================================================
// Plugbet – Sélecteur de pays (bottom sheet)
// ============================================================
// Partagé par les pages d'inscription et de connexion.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/countries.dart';

/// Ouvre le sélecteur de pays et retourne le pays choisi (ou null).
Future<Country?> showCountryPicker(BuildContext context) {
  return showModalBottomSheet<Country>(
    context: context,
    backgroundColor: AppColors.bgDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _CountryPickerSheet(),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = kCountries
        .where((c) => c.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v),
                        style: TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          hintText: 'Rechercher un pays',
                          hintStyle: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    onTap: () => Navigator.pop(context, c),
                    leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                    title: Text(c.name,
                        style: TextStyle(color: AppColors.textPrimary)),
                    trailing: Text('+${c.dial}',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
