// ============================================================
// NotificationProvider – Notifications in-app
// ============================================================
import 'package:flutter/material.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final IconData icon;
  final Color color;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.icon,
    required this.color,
    this.isRead = false,
  });
}

class NotificationProvider extends ChangeNotifier {
  final List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get hasUnread => unreadCount > 0;

  void add({
    required String title,
    required String body,
    required IconData icon,
    required Color color,
  }) {
    _notifications.insert(
      0,
      AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        time: DateTime.now(),
        icon: icon,
        color: color,
      ),
    );
    // Garder max 50 notifications
    if (_notifications.length > 50) _notifications.removeLast();
    notifyListeners();
  }

  void addGoal(String homeTeam, String awayTeam, int homeScore, int awayScore,
      {String? scorer}) {
    add(
      title: 'But ! $homeTeam $homeScore – $awayScore $awayTeam',
      body: scorer != null && scorer.isNotEmpty ? 'Buteur : $scorer' : 'Mises à jour du score',
      icon: Icons.sports_soccer,
      color: const Color(0xFF00E676),
    );
  }

  void addMatchStarted(String homeTeam, String awayTeam) {
    add(
      title: 'Match commencé !',
      body: '$homeTeam vs $awayTeam',
      icon: Icons.play_circle,
      color: const Color(0xFF448AFF),
    );
  }

  void addMatchFinished(String homeTeam, String awayTeam, int homeScore, int awayScore) {
    add(
      title: 'Match terminé',
      body: '$homeTeam $homeScore – $awayScore $awayTeam',
      icon: Icons.flag,
      color: const Color(0xFF8E99A4),
    );
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void dismiss(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clear() {
    _notifications.clear();
    notifyListeners();
  }
}
