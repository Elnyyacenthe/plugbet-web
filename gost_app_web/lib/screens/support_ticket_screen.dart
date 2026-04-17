// ============================================================
// Plugbet – Service Client : conversation d'un ticket
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../services/support_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

const _kCategoryLabels = {
  'general' : 'Général',
  'compte'  : 'Compte',
  'paiement': 'Paiement',
  'jeu'     : 'Jeu',
  'bug'     : 'Bug',
};

class SupportTicketScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const SupportTicketScreen({super.key, required this.ticket});

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _service    = SupportService();
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool   _loading  = true;
  bool   _sending  = false;
  String? _error;

  late String _ticketId;
  late String _status;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _ticketId = widget.ticket['id'] as String;
    _status   = widget.ticket['status'] as String? ?? 'open';
    _loadMessages();
    _subscribeRealtime();
    _markRead();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() { _loading = true; _error = null; });
    try {
      final messages = await _service.getTicketMessages(_ticketId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading  = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _subscribeRealtime() {
    _channel = _service.subscribeTicket(
      _ticketId,
      onMessage: (row) {
        if (!mounted) return;
        setState(() => _messages.add(row));
        _scrollToBottom();
      },
      onStatusChange: (s) {
        if (mounted) setState(() => _status = s);
      },
    );
  }

  Future<void> _markRead() => _service.markRead(_ticketId);

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _status == 'closed') return;

    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await _service.sendMessage(_ticketId, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.neonRed),
      );
      // Remettre le texte si échec
      _msgCtrl.text = text;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'answered': return AppColors.neonGreen;
      case 'closed'  : return AppColors.textMuted;
      default        : return AppColors.neonYellow;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'answered': return 'Répondu';
      case 'closed'  : return 'Fermé';
      default        : return 'Ouvert';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject  = widget.ticket['subject']  as String? ?? '';
    final category = widget.ticket['category'] as String? ?? 'general';
    final isClosed = _status == 'closed';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _statusColor(_status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_statusLabel(_status),
                    style: TextStyle(
                        color: _statusColor(_status),
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 6),
              Text(_kCategoryLabels[category] ?? category,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
            ]),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(children: [
          // ── Bandeau info admin ──────────────────────
          _infoBanner(),
          // ── Messages ────────────────────────────────
          Expanded(child: _buildMessages()),
          // ── Saisie ──────────────────────────────────
          _buildInput(isClosed),
        ]),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.bgBlueNight,
      child: Row(children: [
        Icon(Icons.support_agent, color: AppColors.neonGreen, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Notre équipe répond généralement en moins de 24h.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
          ),
          child: Text(AppLocalizations.of(context)!.supportPlugbet,
              style: TextStyle(color: AppColors.neonGreen, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildMessages() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.neonGreen));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: AppColors.neonRed)));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Décrivez votre problème en détail.\nNotre équipe vous répondra bientôt.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _messageBubble(_messages[i]),
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final isAdmin   = msg['is_admin'] as bool? ?? false;
    final content   = msg['content'] as String? ?? '';
    final createdAt = msg['created_at'] != null
        ? DateTime.tryParse(msg['created_at'] as String)
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            // Avatar admin
            Container(
              width: 30, height: 30,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent, color: AppColors.neonGreen, size: 16),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                if (isAdmin)
                  Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(AppLocalizations.of(context)!.supportPlugbet,
                        style: TextStyle(color: AppColors.neonGreen, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  decoration: BoxDecoration(
                    color: isAdmin ? AppColors.bgCard : AppColors.neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.only(
                      topLeft    : const Radius.circular(16),
                      topRight   : const Radius.circular(16),
                      bottomLeft : Radius.circular(isAdmin ? 4 : 16),
                      bottomRight: Radius.circular(isAdmin ? 16 : 4),
                    ),
                    border: Border.all(
                      color: isAdmin
                          ? AppColors.divider
                          : AppColors.neonGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(content,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4)),
                ),
                if (createdAt != null)
                  Padding(
                    padding: EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text(_formatTime(createdAt),
                        style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(bool isClosed) {
    if (isClosed) {
      return Container(
        padding: EdgeInsets.all(16),
        color: AppColors.bgBlueNight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: AppColors.textMuted, size: 16),
            SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.supportTicketClosed,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
      color: AppColors.bgBlueNight,
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Votre message…',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppColors.bgCard,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.neonGreen),
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _sending
                    ? AppColors.neonGreen.withValues(alpha: 0.4)
                    : AppColors.neonGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _sending
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Icon(Icons.send_rounded, color: Colors.black, size: 20),
            ),
          ),
        ]),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1)  return 'À l\'instant';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inDays < 1)     return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}
