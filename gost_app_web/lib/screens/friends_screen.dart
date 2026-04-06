// ============================================================
// Friends – Liste d'amis, demandes, statut en ligne
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';
import 'user_search_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<FriendModel> _friends = [];
  List<FriendRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final provider = context.read<PlayerProvider>();
    final friends = await provider.getFriends();
    final requests = await provider.getPendingRequests();
    if (mounted) {
      setState(() {
        _friends = friends;
        _requests = requests;
        _loading = false;
      });
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
                    Icon(Icons.people_alt_rounded,
                        color: AppColors.neonBlue, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Amis',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const UserSearchScreen())),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.neonBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add, size: 14, color: AppColors.neonBlue),
                          SizedBox(width: 4),
                          Text('Ajouter', style: TextStyle(
                              color: AppColors.neonBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    if (_requests.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.neonRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_requests.length} demande${_requests.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.neonRed,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Tabs
              Container(
                margin:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.neonBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.neonBlue.withValues(alpha: 0.4)),
                  ),
                  labelColor: AppColors.neonBlue,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  dividerHeight: 0,
                  tabs: [
                    Tab(text: 'Mes amis (${_friends.length})'),
                    Tab(text: 'Demandes (${_requests.length})'),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.neonBlue))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFriendsList(),
                          _buildRequestsList(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 48,
                color: AppColors.textMuted.withValues(alpha: 0.4)),
            SizedBox(height: 12),
            Text(
              'Aucun ami pour le moment',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              'Ajoute des amis depuis le classement\npour organiser des parties !',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.neonBlue,
      backgroundColor: AppColors.bgCard,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _FriendTile(friend: friend);
        },
      ),
    );
  }

  Widget _buildRequestsList() {
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded,
                size: 48,
                color: AppColors.textMuted.withValues(alpha: 0.4)),
            SizedBox(height: 12),
            Text(
              'Aucune demande en attente',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final req = _requests[index];
        return _RequestTile(
          request: req,
          onAccept: () async {
            final provider = context.read<PlayerProvider>();
            final ok = await provider.acceptFriendRequest(req.id, req.fromId);
            if (ok) _loadData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? '${req.fromUsername} ajouté en ami !'
                      : 'Erreur lors de l\'acceptation'),
                  backgroundColor:
                      ok ? AppColors.neonGreen : AppColors.neonRed,
                ),
              );
            }
          },
          onDecline: () async {
            final provider = context.read<PlayerProvider>();
            await provider.declineFriendRequest(req.id);
            _loadData();
          },
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FriendModel friend;
  const _FriendTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    final statusColor = friend.status == 'online'
        ? AppColors.neonGreen
        : friend.status == 'in_game'
            ? AppColors.neonOrange
            : AppColors.textMuted;
    final statusLabel = friend.status == 'online'
        ? 'En ligne'
        : friend.status == 'in_game'
            ? 'En partie'
            : 'Hors ligne';

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: friend.rank.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: friend.rank.color.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(
                    friend.username.isNotEmpty
                        ? friend.username[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: friend.rank.color,
                    ),
                  ),
                ),
              ),
              // Status dot
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgCard, width: 2),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.username,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(friend.rank.icon,
                        size: 12, color: friend.rank.color),
                    SizedBox(width: 4),
                    Text(
                      '${friend.rank.label} • ${friend.xp} XP',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Challenge button
          if (friend.status != 'offline')
            IconButton(
              icon: Icon(Icons.sports_esports_rounded,
                  size: 20, color: AppColors.neonGreen),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Invitation envoyée à ${friend.username} !'),
                    backgroundColor: AppColors.neonGreen,
                  ),
                );
              },
              tooltip: 'Défier',
            ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestTile({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final rank = rankFromXp(request.fromXp);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.neonBlue.withValues(alpha: 0.2)),
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
              border: Border.all(color: rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                request.fromUsername.isNotEmpty
                    ? request.fromUsername[0].toUpperCase()
                    : '?',
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
                  request.fromUsername,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Icon(rank.icon, size: 12, color: rank.color),
                    SizedBox(width: 4),
                    Text(
                      '${rank.label} • ${request.fromXp} XP',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Accept / Decline
          IconButton(
            icon: Icon(Icons.check_circle_rounded,
                size: 28, color: AppColors.neonGreen),
            onPressed: onAccept,
            tooltip: 'Accepter',
          ),
          IconButton(
            icon: Icon(Icons.cancel_rounded,
                size: 28,
                color: AppColors.neonRed.withValues(alpha: 0.7)),
            onPressed: onDecline,
            tooltip: 'Refuser',
          ),
        ],
      ),
    );
  }
}
