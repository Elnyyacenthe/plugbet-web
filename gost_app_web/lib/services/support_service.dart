// ============================================================
// SupportService — Tickets de support et messagerie associee
// ============================================================
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class SupportService {
  static const _log = Logger('SUPPORT');
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Recupere tous les tickets de l'utilisateur courant.
  Future<List<Map<String, dynamic>>> getMyTickets() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await _client
          .from('support_tickets')
          .select('*')
          .eq('user_id', uid)
          .order('updated_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e, s) {
      _log.error('getMyTickets', e, s);
      rethrow;
    }
  }

  /// Cree un nouveau ticket et retourne l'objet insere.
  Future<Map<String, dynamic>?> createTicket({
    required String subject,
    required String category,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final username =
          _client.auth.currentUser?.userMetadata?['username'] as String? ??
              'Joueur';
      final res = await _client.from('support_tickets').insert({
        'user_id': uid,
        'username': username,
        'subject': subject,
        'category': category,
        'status': 'open',
      }).select().single();
      return Map<String, dynamic>.from(res);
    } catch (e, s) {
      _log.error('createTicket', e, s);
      rethrow;
    }
  }

  /// Charge les messages d'un ticket.
  Future<List<Map<String, dynamic>>> getTicketMessages(String ticketId) async {
    try {
      final data = await _client
          .from('support_messages')
          .select('*')
          .eq('ticket_id', ticketId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e, s) {
      _log.error('getTicketMessages', e, s);
      rethrow;
    }
  }

  /// Envoie un message dans un ticket (cote utilisateur).
  Future<void> sendMessage(String ticketId, String content) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _client.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': uid,
        'is_admin': false,
        'content': content,
      });
    } catch (e, s) {
      _log.error('sendMessage', e, s);
      rethrow;
    }
  }

  /// Envoie une image (depuis bytes - cross-platform mobile+web)
  Future<void> sendImageBytes(
    String ticketId,
    Uint8List bytes, {
    String fileExt = 'jpg',
    String? caption,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final ext = fileExt.toLowerCase().isEmpty ? 'jpg' : fileExt.toLowerCase();
      final path = 'support/$ticketId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('chat-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
      final url = _client.storage.from('chat-media').getPublicUrl(path);

      await _client.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': uid,
        'is_admin': false,
        'content': (caption != null && caption.trim().isNotEmpty) ? caption : null,
        'image_url': url,
      });
    } catch (e, s) {
      _log.error('sendImageBytes', e, s);
      rethrow;
    }
  }

  /// Envoie une image (legacy File - mobile/desktop only)
  Future<void> sendImage(String ticketId, File imageFile, {String? caption}) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final ext = imageFile.path.split('.').last.toLowerCase();
      final path = 'support/$ticketId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('chat-media').upload(path, imageFile);
      final url = _client.storage.from('chat-media').getPublicUrl(path);

      await _client.from('support_messages').insert({
        'ticket_id': ticketId,
        'sender_id': uid,
        'is_admin': false,
        'content': (caption != null && caption.trim().isNotEmpty) ? caption : null,
        'image_url': url,
      });
    } catch (e, s) {
      _log.error('sendImage', e, s);
      rethrow;
    }
  }

  /// Marque le ticket comme lu cote user.
  Future<void> markRead(String ticketId) async {
    try {
      await _client
          .from('support_tickets')
          .update({'unread_user': false}).eq('id', ticketId);
    } catch (e) {
      _log.warn('markRead: $e');
    }
  }

  /// Subscribe aux messages d'un ticket en realtime.
  /// [onMessage] est appele a chaque nouveau message.
  /// [onStatusChange] est appele quand le statut du ticket change.
  RealtimeChannel subscribeTicket(
    String ticketId, {
    required void Function(Map<String, dynamic>) onMessage,
    required void Function(String) onStatusChange,
  }) {
    return _client
        .channel('support_ticket_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) {
            onMessage(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ticketId,
          ),
          callback: (payload) {
            final s = payload.newRecord['status'] as String?;
            if (s != null) onStatusChange(s);
          },
        )
        .subscribe();
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
