// ============================================================
// Plugbet – Écran Profil & Historique transactions
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/wallet_provider.dart';
import '../providers/player_provider.dart';
import '../models/player_models.dart';
import '../services/messaging_service.dart';
import '../services/profile_service.dart';
import '../utils/logger.dart';
import '../widgets/profile/transaction_tile.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'user_search_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _log = Logger('PROFILE');
  final _profileService = ProfileService();
  final _messagingService = MessagingService();

  late TabController _tabCtrl;
  List<Map<String, dynamic>> _transactions = [];
  bool _txLoading = true;
  Map<String, dynamic>? _stats;

  // Amis
  List<FriendModel> _friends = [];
  List<FriendRequest> _pendingReceived = [];
  List<Map<String, dynamic>> _pendingSent = [];
  bool _friendsLoading = true;

  Timer? _friendsTimer;
  bool _isVisible = false;

  // Avatar (photo de profil visible par tout le monde)
  String? _myAvatarUrl;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    // Poll only when the Friends tab (index 2) is active
    _friendsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _isVisible && _tabCtrl.index == 2) _loadFriends();
    });
  }

  void _onTabChanged() {
    // Refresh friends when switching TO the friends tab
    if (_tabCtrl.index == 2 && mounted) _loadFriends();
  }

  /// Called by parent when this screen becomes visible/hidden
  void setVisible(bool visible) {
    _isVisible = visible;
    if (visible && mounted) _loadFriends();
  }

  @override
  void dispose() {
    _friendsTimer?.cancel();
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  /// Charge l'URL de l'avatar actuel
  Future<void> _loadMyAvatar() async {
    final url = await _messagingService.getMyAvatarUrl();
    if (mounted) setState(() => _myAvatarUrl = url);
  }

  /// Ouvre le picker et uploade une nouvelle photo de profil
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploadingAvatar = true);
      final url = await _messagingService.uploadAvatar(File(picked.path));
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        if (url != null) _myAvatarUrl = url;
      });
      if (url != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo de profil mise a jour'),
            backgroundColor: AppColors.neonGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, s) {
      _log.error('pickAvatar', e, s);
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadTransactions(),
      _loadStats(),
      _loadFriends(),
      _loadMyAvatar(),
    ]);
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;
    setState(() => _friendsLoading = true);
    try {
      final provider = context.read<PlayerProvider>();
      final friends = await provider.getFriends();
      final received = await provider.getPendingRequests();
      final sent = await _loadSentRequests();
      if (mounted) {
        setState(() {
          _friends = friends;
          _pendingReceived = received;
          _pendingSent = sent;
          _friendsLoading = false;
        });
      }
    } catch (e, s) {
      _log.error('loadFriends', e, s);
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadSentRequests() =>
      _profileService.getSentFriendRequests();

  Future<void> _loadTransactions() async {
    final uid = _profileService.currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _txLoading = false);
      return;
    }

    final ludo = await _profileService.getLudoTransactions();
    final txList = <Map<String, dynamic>>[];

    for (final row in ludo) {
      final bet = row['bet_amount'] as int? ?? 0;
      final status = row['status'] as String? ?? '';
      final isChallenger = row['from_user'] == uid;
      final date = DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now();

      String label;
      int amount;
      String type;

      if (status == 'completed') {
        label = 'Ludo – Partie terminee';
        amount = bet;
        type = 'game';
      } else if (status == 'cancelled') {
        label = 'Ludo – Partie annulee';
        amount = 0;
        type = 'refund';
      } else {
        label = isChallenger ? 'Ludo – Defi lance' : 'Ludo – Defi recu';
        amount = -bet;
        type = 'bet';
      }

      txList.add({
        'label': label,
        'amount': amount,
        'type': type,
        'date': date,
      });
    }

    if (mounted) {
      setState(() {
        _transactions = txList;
        _txLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    final profile = await _profileService.getMyProfile();
    if (profile != null && mounted) {
      setState(() => _stats = profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(t.tabProfile),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.neonGreen,
          labelColor: AppColors.neonGreen,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: t.profileTabInfo.toUpperCase(), icon: const Icon(Icons.person, size: 16)),
            Tab(text: t.profileTabHistory.toUpperCase(), icon: const Icon(Icons.history, size: 16)),
            Tab(
              icon: Badge(
                isLabelVisible: _pendingReceived.isNotEmpty,
                label: Text('${_pendingReceived.length}', style: TextStyle(fontSize: 8)),
                backgroundColor: AppColors.neonRed,
                child: const Icon(Icons.people, size: 16),
              ),
              text: t.profileTabFriends.toUpperCase(),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildProfileTab(wallet),
            _buildHistoryTab(),
            _buildFriendsTab(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 1 : PROFIL
  // ═══════════════════════════════════════════════════════════
  Widget _buildProfileTab(WalletProvider wallet) {
    final user = _profileService.currentUser;
    final email = user?.email ?? 'Anonyme';
    final username = wallet.username.isNotEmpty ? wallet.username : 'Joueur';
    final coins = wallet.coins;
    final createdAt = user?.createdAt != null
        ? DateTime.tryParse(user!.createdAt)
        : null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar + nom
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                // Avatar avec bouton camera pour changer la photo
                GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      UserAvatar(
                        avatarUrl: _myAvatarUrl,
                        username: username,
                        size: 92,
                        showOnlineDot: false,
                      ),
                      if (_uploadingAvatar)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.neonGreen,
                              border: Border.all(
                                  color: AppColors.bgCard, width: 3),
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 16, color: Colors.black),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                Text(username,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text(email,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                if (createdAt != null) ...[
                  SizedBox(height: 4),
                  Text('Membre depuis ${_formatDate(createdAt)}',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ),

          SizedBox(height: 16),

          // Solde
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.neonYellow.withValues(alpha: 0.1),
                AppColors.neonYellow.withValues(alpha: 0.03),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonYellow, size: 32),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SOLDE',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    Text('$coins coins',
                        style: TextStyle(
                            color: AppColors.neonYellow,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Stats rapides
          Row(
            children: [
              Expanded(child: _statCard('Parties jouées',
                  '${_stats?['games_played'] ?? 0}', AppColors.neonBlue)),
              SizedBox(width: 8),
              Expanded(child: _statCard('Victoires',
                  '${_stats?['wins'] ?? 0}', AppColors.neonGreen)),
              SizedBox(width: 8),
              Expanded(child: _statCard('Défaites',
                  '${_stats?['losses'] ?? 0}', AppColors.neonRed)),
            ],
          ),

          SizedBox(height: 24),

          // Actions compte
          _buildAccountActions(),
        ],
      ),
    );
  }

  Widget _buildAccountActions() {
    final user = _profileService.currentUser;
    final isAnonymous = _profileService.isAnonymous;
    final isLoggedIn = user != null;
    final t = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.manage_accounts, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('COMPTE',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          SizedBox(height: 12),

          if (isLoggedIn && !isAnonymous) ...[
            // Connecté avec email
            _accountRow(Icons.email_outlined, user.email ?? '',
                AppColors.textSecondary, null),
            SizedBox(height: 8),
            _accountActionBtn(t.profileLogout, Icons.logout, AppColors.neonRed, () async {
              await _profileService.signOut();
              if (mounted) {
                context.read<WalletProvider>().refresh();
                setState(() {});
              }
            }),
          ] else ...[
            // Anonyme ou pas connecté
            Text(t.profileAnonymous,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _accountActionBtn(t.authSignIn, Icons.login, AppColors.neonGreen, () async {
                    final ok = await Navigator.push<bool>(context,
                        MaterialPageRoute(builder: (_) => AuthScreen(startWithSignUp: false)));
                    if (ok == true && mounted) {
                      context.read<WalletProvider>().refresh();
                      _loadData();
                      setState(() {});
                    }
                  }),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _accountActionBtn('Créer un compte', Icons.person_add, AppColors.neonBlue, () async {
                    final ok = await Navigator.push<bool>(context,
                        MaterialPageRoute(builder: (_) => AuthScreen(startWithSignUp: true)));
                    if (ok == true && mounted) {
                      context.read<WalletProvider>().refresh();
                      _loadData();
                      setState(() {});
                    }
                  }),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _accountRow(IconData icon, String text, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 8),
          Expanded(child: Text(text,
              style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _accountActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(width: 6),
            Text(label, style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w900)),
          SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 2 : HISTORIQUE
  // ═══════════════════════════════════════════════════════════
  Widget _buildHistoryTab() {
    if (_txLoading) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen));
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: AppColors.textMuted, size: 48),
            SizedBox(height: 12),
            Text('Aucune transaction',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Jouez des parties pour voir l\'historique ici',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final tx = _transactions[i];
        return TransactionTile(
          label: tx['label'] as String,
          amount: tx['amount'] as int,
          date: tx['date'] as DateTime,
          type: tx['type'] as String,
        );
      },
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ═══════════════════════════════════════════════════════════
  // TAB 3 : AMIS
  // ═══════════════════════════════════════════════════════════
  Widget _buildFriendsTab() {
    if (_friendsLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.neonGreen));
    }

    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bgCard,
      onRefresh: _loadFriends,
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Bouton ajouter
          GestureDetector(
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const UserSearchScreen()));
              _loadFriends();
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add, color: AppColors.neonBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Rechercher et ajouter un ami',
                      style: TextStyle(color: AppColors.neonBlue,
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),

          // Demandes reçues
          if (_pendingReceived.isNotEmpty) ...[
            SizedBox(height: 20),
            _friendSectionHeader('DEMANDES REÇUES', _pendingReceived.length, AppColors.neonOrange),
            SizedBox(height: 8),
            ..._pendingReceived.map((req) => _receivedRequestCard(req)),
          ],

          // Demandes envoyées en attente
          if (_pendingSent.where((s) => s['status'] == 'pending').isNotEmpty) ...[
            SizedBox(height: 20),
            _friendSectionHeader('DEMANDES ENVOYÉES',
                _pendingSent.where((s) => s['status'] == 'pending').length, AppColors.neonBlue),
            SizedBox(height: 8),
            ..._pendingSent.where((s) => s['status'] == 'pending').map((s) => _sentRequestCard(s)),
          ],

          // Mes amis
          SizedBox(height: 20),
          _friendSectionHeader('MES AMIS', _friends.length, AppColors.neonGreen),
          SizedBox(height: 8),
          if (_friends.isEmpty)
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 40,
                      color: AppColors.textMuted.withValues(alpha: 0.3)),
                  SizedBox(height: 8),
                  Text('Aucun ami pour le moment',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            )
          else
            ..._friends.map((f) => _friendCard(f)),

          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _friendSectionHeader(String title, int count, Color color) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _receivedRequestCard(FriendRequest req) {
    final rank = rankFromXp(req.fromXp);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: rank.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                req.fromUsername.isNotEmpty ? req.fromUsername[0].toUpperCase() : '?',
                style: TextStyle(color: rank.color, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req.fromUsername,
                    style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Row(children: [
                  Icon(rank.icon, size: 12, color: rank.color),
                  SizedBox(width: 4),
                  Text('${rank.label} • ${req.fromXp} XP',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
                SizedBox(height: 2),
                Text('Reçue le ${_formatDate(req.sentAt)}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final provider = context.read<PlayerProvider>();
                  final ok = await provider.acceptFriendRequest(req.id, req.fromId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? '${req.fromUsername} ajouté en ami !'
                          : 'Erreur'),
                      backgroundColor: ok ? AppColors.neonGreen : AppColors.neonRed,
                    ));
                    _loadFriends();
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.check, color: AppColors.neonGreen, size: 18),
                ),
              ),
              SizedBox(width: 6),
              GestureDetector(
                onTap: () async {
                  final provider = context.read<PlayerProvider>();
                  await provider.declineFriendRequest(req.id);
                  if (mounted) _loadFriends();
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.close, color: AppColors.neonRed, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sentRequestCard(Map<String, dynamic> req) {
    final username = req['to_username'] as String? ?? 'Joueur';
    final date = DateTime.tryParse(req['created_at'] as String? ?? '') ?? DateTime.now();
    final status = req['status'] as String? ?? 'pending';

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(color: AppColors.neonBlue, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Envoyée le ${_formatDate(date)}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status == 'pending' ? 'En attente' : status,
                style: TextStyle(color: AppColors.neonYellow,
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _friendCard(FriendModel friend) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: friend.rank.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: friend.rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                friend.username.isNotEmpty ? friend.username[0].toUpperCase() : '?',
                style: TextStyle(color: friend.rank.color, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.username,
                    style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Row(children: [
                  Icon(friend.rank.icon, size: 12, color: friend.rank.color),
                  SizedBox(width: 4),
                  Text('${friend.rank.label} • ${friend.xp} XP',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
              ],
            ),
          ),
          Icon(Icons.chat_bubble_outline, color: AppColors.neonGreen, size: 18),
        ],
      ),
    );
  }
}
