// ============================================================
// Plugbet – Service Client : liste des tickets
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'support_ticket_screen.dart';

// Catégories disponibles
const _kCategories = ['general', 'compte', 'paiement', 'jeu', 'bug'];
const _kCategoryLabels = {
  'general' : 'Général',
  'compte'  : 'Compte',
  'paiement': 'Paiement',
  'jeu'     : 'Jeu',
  'bug'     : 'Bug',
};

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        setState(() { _error = 'Connectez-vous pour accéder au support.'; _loading = false; });
        return;
      }
      final data = await _client
          .from('support_tickets')
          .select('*')
          .eq('user_id', uid)
          .order('updated_at', ascending: false);
      setState(() { _tickets = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openNewTicketDialog() async {
    final subjectCtrl = TextEditingController();
    String category = 'general';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Nouveau ticket', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Catégorie', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              SizedBox(height: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: category,
                    isExpanded: true,
                    dropdownColor: AppColors.bgCard,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    items: _kCategories.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(_kCategoryLabels[c] ?? c),
                    )).toList(),
                    onChanged: (v) => setS(() => category = v!),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text('Sujet', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              SizedBox(height: 6),
              TextField(
                controller: subjectCtrl,
                maxLength: 120,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Décrivez brièvement votre problème…',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  counterStyle: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Créer', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final subject = subjectCtrl.text.trim();
    if (subject.isEmpty) return;

    try {
      final uid   = _client.auth.currentUser!.id;
      final uname = _client.auth.currentUser?.userMetadata?['username'] as String? ?? 'Joueur';

      final res = await _client.from('support_tickets').insert({
        'user_id' : uid,
        'username': uname,
        'subject' : subject,
        'category': category,
        'status'  : 'open',
      }).select().single();

      if (!mounted) return;
      // Ouvrir directement le ticket créé
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => SupportTicketScreen(ticket: Map<String, dynamic>.from(res)),
      ));
      _loadTickets();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.neonRed),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'answered': return AppColors.neonGreen;
      case 'closed'  : return AppColors.textMuted;
      default        : return AppColors.neonYellow;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'answered': return 'Répondu';
      case 'closed'  : return 'Fermé';
      default        : return 'Ouvert';
    }
  }

  IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'paiement': return Icons.credit_card;
      case 'compte'  : return Icons.manage_accounts;
      case 'jeu'     : return Icons.sports_esports;
      case 'bug'     : return Icons.bug_report;
      default        : return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _client.auth.currentUser != null;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Row(
          children: [
            Icon(Icons.support_agent, color: AppColors.neonGreen, size: 22),
            SizedBox(width: 10),
            Text('Service Client',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          if (_loading)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonGreen)),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh, color: AppColors.textSecondary),
              onPressed: _loadTickets,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _buildBody(isLoggedIn),
      ),
      floatingActionButton: isLoggedIn
          ? FloatingActionButton.extended(
              onPressed: _openNewTicketDialog,
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              icon: Icon(Icons.add),
              label: Text('Nouveau ticket', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
    );
  }

  Widget _buildBody(bool isLoggedIn) {
    if (!isLoggedIn) {
      return _centeredMessage(
        Icons.lock_outline, AppColors.neonYellow,
        'Connexion requise',
        'Connectez-vous pour contacter le support.',
      );
    }
    if (_loading) return Center(child: CircularProgressIndicator(color: AppColors.neonGreen));
    if (_error != null) return _centeredMessage(Icons.error_outline, AppColors.neonRed, 'Erreur', _error!);
    if (_tickets.isEmpty) return _emptyState();
    return RefreshIndicator(
      color: AppColors.neonGreen,
      onRefresh: _loadTickets,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _tickets.length,
        separatorBuilder: (_, __) => SizedBox(height: 10),
        itemBuilder: (_, i) => _ticketCard(_tickets[i]),
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final status   = t['status'] as String? ?? 'open';
    final category = t['category'] as String? ?? 'general';
    final subject  = t['subject'] as String? ?? '';
    final unread   = t['unread_user'] as bool? ?? false;
    final updated  = t['updated_at'] != null
        ? DateTime.tryParse(t['updated_at'] as String)
        : null;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SupportTicketScreen(ticket: t),
        ));
        _loadTickets();
      },
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread
                ? AppColors.neonGreen.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            // Icône catégorie
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_categoryIcon(category), color: _statusColor(status), size: 20),
            ),
            SizedBox(width: 12),
            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 14,
                          )),
                    ),
                    if (unread)
                      Container(
                        width: 8, height: 8,
                        margin: EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen, shape: BoxShape.circle),
                      ),
                  ]),
                  SizedBox(height: 4),
                  Row(children: [
                    // Badge statut
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_statusLabel(status),
                          style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(width: 8),
                    // Badge catégorie
                    Text(_kCategoryLabels[category] ?? category,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const Spacer(),
                    if (updated != null)
                      Text(_formatDate(updated),
                          style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ],
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent, color: AppColors.neonGreen, size: 38),
            ),
            SizedBox(height: 20),
            Text('Aucun ticket ouvert',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Vous avez un problème ou une question ?\nCréez un ticket et notre équipe vous répond.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openNewTicketDialog,
              icon: Icon(Icons.add),
              label: Text('Créer mon premier ticket',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centeredMessage(IconData icon, Color color, String title, String msg) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 48),
          SizedBox(height: 16),
          Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
