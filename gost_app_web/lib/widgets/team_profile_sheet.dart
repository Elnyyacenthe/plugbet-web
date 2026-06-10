// ============================================================
// TeamProfileSheet — Bottom sheet fiche equipe
// ============================================================
// Affichee au tap sur un logo d'equipe dans la fiche match :
//   - Nom, pays, annee fondation
//   - Stade (nom, ville, capacite, surface)
//   - Coach
//   - Squad (joueurs avec position + numero + age + pays)
//
// Source : StatpalService.getTeamProfile(teamId) (cache 1h).
// Soccer uniquement (endpoint pas dispo pour NBA dans notre plan).
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';

Future<void> showTeamProfileSheet(BuildContext context, String teamId,
    {required String fallbackName}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TeamProfileSheet(teamId: teamId, fallbackName: fallbackName),
  );
}

class _TeamProfileSheet extends StatefulWidget {
  final String teamId;
  final String fallbackName;
  const _TeamProfileSheet({required this.teamId, required this.fallbackName});

  @override
  State<_TeamProfileSheet> createState() => _TeamProfileSheetState();
}

class _TeamProfileSheetState extends State<_TeamProfileSheet> {
  TeamProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await StatpalService.instance.getTeamProfile(widget.teamId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.85),
      padding: EdgeInsets.only(
        top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(40),
            child: CircularProgressIndicator(color: AppColors.neonGreen),
          )
        else if (_profile == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.error_outline,
                  size: 32, color: AppColors.textMuted),
              const SizedBox(height: 8),
              Text(widget.fallbackName,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Profil indisponible',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          )
        else
          Flexible(child: _buildContent(_profile!)),
      ]),
    );
  }

  Widget _buildContent(TeamProfile p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(p.country.toUpperCase(),
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 10, fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
          ),
          if (p.founded != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('FONDÉ ${p.founded}',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text(p.name,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),

        // Stade
        if (p.venueName != null) _infoCard(
          icon: Icons.stadium,
          title: p.venueName!,
          subtitle: [
            if (p.venueCity != null) p.venueCity!,
            if (p.venueCapacity != null) '${p.venueCapacity} places',
            if (p.venueSurface != null) p.venueSurface!,
          ].join(' • '),
        ),

        // Coach
        if (p.coachName != null) ...[
          const SizedBox(height: 8),
          _infoCard(
            icon: Icons.person,
            title: p.coachName!,
            subtitle: 'Entraîneur principal',
          ),
        ],

        // Squad
        if (p.squad.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('EFFECTIF (${p.squad.length})',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10, fontWeight: FontWeight.w900,
                letterSpacing: 1)),
          const SizedBox(height: 8),
          ...p.squad.map(_playerRow),
        ],
      ]),
    );
  }

  Widget _infoCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.neonGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w800)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _playerRow(TeamPlayer p) {
    final n = p.number != null ? '#${p.number}' : '';
    final age = p.age != null ? '${p.age} ans' : '';
    final ctx = p.country ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        if (n.isNotEmpty) ...[
          Container(
            width: 24, height: 24, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(n,
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 10, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12, fontWeight: FontWeight.w700)),
              if (p.position != null || age.isNotEmpty || ctx.isNotEmpty)
                Text([
                  if (p.position != null) p.position!,
                  if (age.isNotEmpty) age,
                  if (ctx.isNotEmpty) ctx,
                ].join(' • '),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ]),
    );
  }
}
