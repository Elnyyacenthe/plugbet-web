// ============================================================
// UserSearchScreen – Recherche tous les utilisateurs de l'app
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';
import 'user_profile_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final myId = _client.auth.currentUser?.id;
    try {
      final data = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins')
          .neq('id', myId ?? '')
          .order('xp', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _users = (data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() { _users = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    final myId = _client.auth.currentUser?.id;
    try {
      final data = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins')
          .ilike('username', '%${query.trim()}%')
          .neq('id', myId ?? '')
          .limit(30);
      if (mounted) {
        setState(() {
          _users = (data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Icon(Icons.person_search_rounded,
                        color: AppColors.neonGreen, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Trouver des joueurs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // Barre de recherche
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par pseudo...',
                      hintStyle: TextStyle(
                          color: AppColors.textMuted, fontSize: 15),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: AppColors.textMuted),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon:
                                  Icon(Icons.close, size: 18),
                              color: AppColors.textMuted,
                              onPressed: () {
                                _searchController.clear();
                                setState(() { _users = []; _loading = false; });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),
              // Liste
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.neonGreen))
                    : _users.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            color: AppColors.neonGreen,
                            backgroundColor: AppColors.bgCard,
                            onRefresh: _loadAll,
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: _users.length,
                              itemBuilder: (context, i) =>
                                  _UserTile(user: _users[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              hasQuery ? Icons.person_off_outlined : Icons.person_search_rounded,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3)),
          SizedBox(height: 12),
          Text(
              hasQuery
                  ? 'Aucun joueur trouvé'
                  : 'Tapez un pseudo pour rechercher',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ── Tuile utilisateur ─────────────────────────────────────
class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String? ?? 'Joueur';
    final xp = (user['xp'] as int?) ?? 0;
    final rank = rankFromXp(xp);
    final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userId: user['id'] as String,
            username: username,
          ),
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: rank.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: rank.color.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: rank.color,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(rank.icon, size: 12, color: rank.color),
                      SizedBox(width: 4),
                      Text(
                        '${rank.label} • $xp XP',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _AddFriendBtn(userId: user['id'] as String),
          ],
        ),
      ),
    );
  }
}

class _AddFriendBtn extends StatefulWidget {
  final String userId;
  const _AddFriendBtn({required this.userId});
  @override
  State<_AddFriendBtn> createState() => _AddFriendBtnState();
}

class _AddFriendBtnState extends State<_AddFriendBtn> {
  String _status = 'idle'; // idle, sending, sent, already, friend

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Vérifier si déjà amis
      final friendship = await Supabase.instance.client
          .from('friendships')
          .select('id')
          .eq('user_id', uid)
          .eq('friend_id', widget.userId)
          .maybeSingle();
      if (friendship != null) {
        if (mounted) setState(() => _status = 'friend');
        return;
      }
      // Vérifier si demande déjà envoyée
      final sent = await Supabase.instance.client
          .from('friend_requests')
          .select('id')
          .eq('from_id', uid)
          .eq('to_id', widget.userId)
          .eq('status', 'pending')
          .maybeSingle();
      if (sent != null) {
        if (mounted) setState(() => _status = 'already');
        return;
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    setState(() => _status = 'sending');
    final ok = await context.read<PlayerProvider>().sendFriendRequest(widget.userId);
    if (mounted) {
      setState(() => _status = ok ? 'sent' : 'idle');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Demande envoyée !' : 'Erreur lors de l\'envoi'),
        backgroundColor: ok ? AppColors.neonGreen : AppColors.neonRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == 'friend') {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.neonGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('Ami', style: TextStyle(
            color: AppColors.neonGreen, fontSize: 11, fontWeight: FontWeight.w700)),
      );
    }
    if (_status == 'sent' || _status == 'already') {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.neonYellow.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('En attente', style: TextStyle(
            color: AppColors.neonYellow, fontSize: 11, fontWeight: FontWeight.w700)),
      );
    }
    return GestureDetector(
      onTap: _status == 'sending' ? null : _send,
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.neonBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.4)),
        ),
        child: _status == 'sending'
            ? SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonBlue))
            : Icon(Icons.person_add, color: AppColors.neonBlue, size: 18),
      ),
    );
  }
}
