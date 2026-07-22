// ============================================================
// Plugbet – Écran Profil & Historique transactions
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/wallet_provider.dart';
import '../providers/player_provider.dart';
import '../models/player_models.dart';
import '../services/messaging_service.dart';
import '../services/profile_service.dart';
import '../services/supabase_service.dart';
import '../services/hive_service.dart';
import '../services/kpay_service.dart';
import '../utils/logger.dart';
import '../widgets/profile/transaction_tile.dart';
import '../widgets/user_avatar.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'user_search_screen.dart';
import 'my_payments_screen.dart';
import 'settings_screen.dart';
import 'bonus_codes_screen.dart';
import '../services/bonus_service.dart';

class ProfileScreen extends StatefulWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;

  /// Ouvre directement la fenetre de depot a l'arrivee (ex: depuis la
  /// proposition de recharge affichee aux nouveaux comptes).
  final bool openDeposit;

  const ProfileScreen({
    super.key,
    required this.hiveService,
    required this.supabaseService,
    this.openDeposit = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _log = Logger('PROFILE');
  final _profileService = ProfileService();
  final _messagingService = MessagingService();
  final _kpayService = KpayService();
  final _bonusService = BonusService();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      if (widget.openDeposit && mounted) _showDepositDialog();
    });
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

    final txList = <Map<String, dynamic>>[];

    // 1. Charger les transactions Ludo
    final ludo = await _profileService.getLudoTransactions();
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

    // 2. Charger les transactions K-Pay
    try {
      final kpayTx = await _kpayService.getMyTransactions();
      for (final row in kpayTx) {
        final txType = row['transaction_type'] as String? ?? '';
        final status = row['status'] as String? ?? '';
        final amount = row['amount'] as int? ?? 0;
        final date = DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now();

        String label;
        int displayAmount;
        String type;
        // Motif affiche sous le libelle (ex: raison d'un echec K-Pay :
        // "Solde insuffisant sur le compte Mobile Money du client.")
        String? subtitle;
        final message = (row['message'] as String?)?.trim();

        if (txType == 'DEPOSIT') {
          if (status == 'SUCCESS') {
            label = 'Depot Mobile Money';
            displayAmount = amount;
            type = 'deposit';
          } else if (status == 'FAILED') {
            label = 'Depot echoue';
            displayAmount = 0;
            type = 'failed';
            subtitle = message;
          } else {
            label = 'Depot en attente';
            displayAmount = 0;
            type = 'pending';
          }
        } else if (txType == 'WITHDRAW') {
          if (status == 'SUCCESS') {
            label = 'Retrait Mobile Money';
            displayAmount = -amount;
            type = 'withdrawal';
          } else if (status == 'FAILED') {
            label = 'Retrait echoue (rembourse)';
            displayAmount = 0;
            type = 'refund';
            subtitle = message;
          } else {
            label = 'Retrait en cours';
            displayAmount = -amount;
            type = 'pending';
          }
        } else {
          continue; // Ignorer les types inconnus
        }

        txList.add({
          'label': label,
          'amount': displayAmount,
          'type': type,
          'date': date,
          'subtitle': subtitle,
        });
      }
    } catch (e, s) {
      _log.error('loadKpayTransactions', e, s);
    }

    // 3. Trier par date décroissante (plus récent en premier)
    txList.sort((a, b) {
      final dateA = a['date'] as DateTime;
      final dateB = b['date'] as DateTime;
      return dateB.compareTo(dateA);
    });

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
      backgroundColor: AppColors.bettingBackground,
      body: SafeArea(
        child: Column(
          children: [
            _profileTopBar(t),
            _profileTabs(t),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildProfileTab(wallet),
                  _buildHistoryTab(),
                  _buildFriendsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTopBar(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              Icons.person_rounded,
              color: AppSurfaces.inkOn(AppColors.primary),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tabProfile,
                  style: TextStyle(
                    color: AppColors.bettingTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'COMPTE · WALLET · AMIS',
                  style: TextStyle(
                    color: AppColors.bettingTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    hiveService: widget.hiveService,
                    supabaseService: widget.supabaseService,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.bettingSurfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.bettingBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.bettingSoftShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.settings_rounded,
                color: AppColors.bettingTextPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTabs(AppLocalizations t) {
    return Container(
      height: 64,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bettingSurfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bettingBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabCtrl,
        dividerColor: AppColors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppColors.primaryInk.withValues(alpha: 0.5)),
        ),
        labelColor: AppColors.primaryInk,
        unselectedLabelColor: AppColors.bettingTextSecondary,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        unselectedLabelStyle:
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        tabs: [
          Tab(
            text: t.profileTabInfo.toUpperCase(),
            icon: const Icon(Icons.person, size: 15),
          ),
          Tab(
            text: t.profileTabHistory.toUpperCase(),
            icon: const Icon(Icons.history, size: 15),
          ),
          Tab(
            icon: Badge(
              isLabelVisible: _pendingReceived.isNotEmpty,
              label: Text('${_pendingReceived.length}',
                  style: TextStyle(fontSize: 8)),
              backgroundColor: AppColors.neonRed,
              child: const Icon(Icons.people, size: 15),
            ),
            text: t.profileTabFriends.toUpperCase(),
          ),
        ],
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
    final createdAt =
        user?.createdAt != null ? DateTime.tryParse(user!.createdAt) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      child: Column(
        children: [
          _profileHeroCard(
            username: username,
            email: email,
            createdAt: createdAt,
          ),
          const SizedBox(height: 14),
          _walletPanel(coins),
          const SizedBox(height: 12),
          _bonusShortcut(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: 'Dépôt',
                  icon: Icons.add_circle_outline,
                  color: AppColors.primary,
                  onTap: _showDepositDialog,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionButton(
                  label: 'Retrait',
                  icon: Icons.remove_circle_outline,
                  color: AppColors.neonOrange,
                  onTap: _showWithdrawalDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _paymentsShortcut(),
          const SizedBox(height: 16),
          Builder(builder: (_) {
            final played = (_stats?['games_played'] as int?) ?? 0;
            final won = (_stats?['games_won'] as int?) ?? 0;
            final lost = (played - won).clamp(0, played);
            return Row(
              children: [
                Expanded(
                  child: _statCard('Parties', '$played', AppColors.neonBlue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard('Victoires', '$won', AppColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard('Défaites', '$lost', AppColors.neonOrange),
                ),
              ],
            );
          }),
          const SizedBox(height: 18),
          _buildAccountActions(),
        ],
      ),
    );
  }

  Widget _profileHeroCard({
    required String username,
    required String email,
    required DateTime? createdAt,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.bettingSurfaceElevated,
            AppColors.bettingViolet.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bettingBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingAvatar ? null : _pickAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  avatarUrl: _myAvatarUrl,
                  username: username,
                  size: 78,
                  showOnlineDot: false,
                ),
                if (_uploadingAvatar)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.bettingImageScrim,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
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
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        border: Border.all(
                          color: AppColors.bettingSurfaceElevated,
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 15,
                        color: AppSurfaces.inkOn(AppColors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.bettingTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.bettingTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primaryInk.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    createdAt == null
                        ? 'Membre PlugBet'
                        : 'Membre depuis ${_formatDate(createdAt)}',
                    style: TextStyle(
                      color: AppColors.primaryInk,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletPanel(int coins) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bettingSurfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bettingBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.neonYellow.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.neonYellow.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.neonYellow,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOLDE DISPONIBLE',
                  style: TextStyle(
                    color: AppColors.bettingTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$coins FCFA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.bettingTextPrimary,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.bettingInactive, size: 20),
        ],
      ),
    );
  }

  /// Raccourci vers l'ecran "Mes bonus" (codes bonus PlugSafe / PlugShield /
  /// PlugBoost). Affiche le nombre de bonus actifs quand il y en a.
  Widget _bonusShortcut() {
    const gold = Color(0xFFFFB020);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BonusCodesScreen()),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.card_giftcard_rounded, color: gold, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mes bonus',
                      style: TextStyle(
                          color: AppColors.bettingTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900)),
                  Text('Codes PlugSafe / PlugShield / PlugBoost',
                      style: TextStyle(
                          color: AppColors.bettingTextSecondary,
                          fontSize: 11.5)),
                ],
              ),
            ),
            FutureBuilder<List<BonusCode>>(
              future: _bonusService.getMyBonusCodes(),
              builder: (ctx, snap) {
                final n =
                    (snap.data ?? const []).where((c) => c.isActive).length;
                if (n <= 0) {
                  return Icon(Icons.chevron_right,
                      color: AppColors.bettingInactive, size: 20);
                }
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$n',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentsShortcut() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyPaymentsScreen()),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bettingSurfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.bettingBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.history, color: AppColors.neonBlue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mes paiements Mobile Money',
                style: TextStyle(
                  color: AppColors.bettingTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppColors.bettingTextSecondary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountActions() {
    final user = _profileService.currentUser;
    final isAnonymous = _profileService.isAnonymous;
    final isLoggedIn = user != null;
    final t = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bettingSurfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bettingBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.manage_accounts,
                  size: 16, color: AppColors.bettingTextSecondary),
              const SizedBox(width: 8),
              Text('COMPTE',
                  style: TextStyle(
                      color: AppColors.bettingTextSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          SizedBox(height: 12),
          if (isLoggedIn && !isAnonymous) ...[
            // Badge type de compte
            Builder(builder: (_) {
              final accountType = SupabaseService().accountType;
              final isOfficial = accountType == 'official';
              final badgeText =
                  isOfficial ? t.profileOfficialBadge : t.profileQuickBadge;
              final badgeColor =
                  isOfficial ? AppColors.neonGreen : AppColors.neonYellow;
              return Row(
                children: [
                  Icon(Icons.email_outlined,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(user.email ?? '',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13))),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(badgeText,
                        style: TextStyle(
                            color: badgeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            }),
            SizedBox(height: 8),
            // Bouton upgrade si compte rapide/google/phone (pas officiel)
            if (SupabaseService().accountType != 'official')
              _accountActionBtn(t.profileUpgradeTitle, Icons.verified_user,
                  AppColors.neonGreen, () {
                _showUpgradeDialog(t);
              }),
            if (SupabaseService().accountType != 'official')
              SizedBox(height: 8),
            _accountActionBtn('Modifier le pseudo', Icons.person_outline,
                AppColors.neonPurple, () {
              _showChangeUsernameDialog();
            }),
            SizedBox(height: 8),
            _accountActionBtn(
                t.profileChangePassword, Icons.lock_outline, AppColors.neonBlue,
                () {
              _showChangePasswordDialog(t);
            }),
            SizedBox(height: 8),
            _accountActionBtn(t.profileLogout, Icons.logout, AppColors.neonRed,
                () async {
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
                  child: _accountActionBtn(
                      t.authSignIn, Icons.login, AppColors.neonGreen, () async {
                    final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()));
                    if (ok == true && mounted) {
                      context.read<WalletProvider>().refresh();
                      _loadData();
                      setState(() {});
                    }
                  }),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _accountActionBtn(
                      'Créer un compte', Icons.person_add, AppColors.neonBlue,
                      () async {
                    final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SignupScreen()));
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

  void _showUpgradeDialog(AppLocalizations t) {
    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? error;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t.profileUpgradeTitle,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.profileUpgradeSubtitle,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                SizedBox(height: 16),
                if (error != null) ...[
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(error!,
                        style:
                            TextStyle(color: AppColors.neonRed, fontSize: 12)),
                  ),
                  SizedBox(height: 12),
                ],
                TextField(
                  controller: fullNameCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: t.profileFullName,
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.person,
                        color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: t.authEmail,
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: t.profilePhoneNumber,
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.phone, color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.commonCancel,
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final name = fullNameCtrl.text.trim();
                      final email = emailCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      if (name.isEmpty || (email.isEmpty && phone.isEmpty)) {
                        setS(() => error = t.profileUpgradeSubtitle);
                        return;
                      }
                      setS(() {
                        loading = true;
                        error = null;
                      });
                      final err =
                          await SupabaseService().upgradeToOfficialAccount(
                        fullName: name,
                        email: email.isNotEmpty ? email : null,
                        phone: phone.isNotEmpty ? phone : null,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setS(() {
                          loading = false;
                          error = err;
                        });
                      } else {
                        Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t.profileUpgradeSuccess),
                              backgroundColor: AppColors.neonGreen,
                            ),
                          );
                          setState(() {});
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(t.commonConfirm,
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeUsernameDialog() {
    final currentUsername = context.read<WalletProvider>().username;
    final ctrl = TextEditingController(text: currentUsername);
    String? error;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person, color: AppColors.neonPurple, size: 20),
              const SizedBox(width: 10),
              Text('Modifier le pseudo',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ce pseudo sera affiche aux autres joueurs.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 14),
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(error!,
                      style: TextStyle(color: AppColors.neonRed, fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Nouveau pseudo',
                  hintStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 14),
                  prefixIcon: Icon(Icons.alternate_email,
                      color: AppColors.textMuted, size: 20),
                  filled: true,
                  fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.neonPurple, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child:
                  Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final newName = ctrl.text.trim();
                      if (newName.length < 3) {
                        setS(() => error = 'Min 3 caracteres');
                        return;
                      }
                      if (newName == currentUsername) {
                        setS(() => error = 'C\'est deja ton pseudo actuel');
                        return;
                      }
                      setS(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        final supa = SupabaseService();
                        final uid = supa.currentUserId;
                        if (uid == null) {
                          setS(() {
                            loading = false;
                            error = 'Non connecte';
                          });
                          return;
                        }
                        // Unicite
                        final existing = await supa.client
                            .from('user_profiles')
                            .select('id')
                            .eq('username', newName)
                            .neq('id', uid)
                            .maybeSingle();
                        if (existing != null) {
                          setS(() {
                            loading = false;
                            error =
                                'Ce pseudo est deja utilise. Choisis-en un autre.';
                          });
                          return;
                        }
                        // Compte rapide : la reconnexion derive l'email du
                        // pseudo -> il faut synchroniser l'email d'auth,
                        // sinon l'utilisateur ne pourrait plus se reconnecter.
                        if (supa.accountType == 'quick') {
                          final emailErr =
                              await supa.updateQuickAccountEmail(newName);
                          if (emailErr != null) {
                            setS(() {
                              loading = false;
                              error = emailErr;
                            });
                            return;
                          }
                        }
                        await supa.client.from('user_profiles').update({
                          'username': newName,
                          'updated_at': DateTime.now().toIso8601String(),
                        }).eq('id', uid);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        await context.read<WalletProvider>().refresh();
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Pseudo mis a jour'),
                            backgroundColor: AppColors.neonGreen,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        final msg = e.toString().toLowerCase();
                        setS(() {
                          loading = false;
                          error = (msg.contains('duplicate') ||
                                  msg.contains('23505') ||
                                  msg.contains('unique'))
                              ? 'Ce pseudo est deja utilise. Choisis-en un autre.'
                              : 'Erreur: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Valider',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(AppLocalizations t) {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(t.profileChangePassword,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(error!,
                      style: TextStyle(color: AppColors.neonRed, fontSize: 12)),
                ),
                SizedBox(height: 12),
              ],
              TextField(
                controller: newCtrl,
                obscureText: true,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: t.profileNewPassword,
                  labelStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: t.profileConfirmPassword,
                  labelStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgElevated,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t.commonCancel,
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final pwd = newCtrl.text.trim();
                      final confirm = confirmCtrl.text.trim();
                      if (pwd.length < 6) {
                        setS(() => error = t.profilePasswordTooShort);
                        return;
                      }
                      if (pwd != confirm) {
                        setS(() => error = t.profilePasswordMismatch);
                        return;
                      }
                      setS(() {
                        loading = true;
                        error = null;
                      });
                      final err = await SupabaseService().changePassword(pwd);
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setS(() {
                          loading = false;
                          error = err;
                        });
                      } else {
                        Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t.profilePasswordChanged),
                              backgroundColor: AppColors.neonGreen,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(t.profileChange,
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bettingSurfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.bettingTextSecondary,
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

    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bettingSurface,
      onRefresh: _loadTransactions,
      child: _transactions.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                Icon(Icons.history, color: AppColors.textMuted, size: 48),
                SizedBox(height: 12),
                Text('Aucune transaction',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Tirez vers le bas pour actualiser',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            )
          : ListView.separated(
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
                  subtitle: tx['subtitle'] as String?,
                );
              },
            ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ═══════════════════════════════════════════════════════════
  // TAB 3 : AMIS
  // ═══════════════════════════════════════════════════════════
  Widget _buildFriendsTab() {
    if (_friendsLoading) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen));
    }

    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bettingSurface,
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
                border: Border.all(
                    color: AppColors.neonBlue.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add, color: AppColors.neonBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Rechercher et ajouter un ami',
                      style: TextStyle(
                          color: AppColors.neonBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),

          // Demandes reçues
          if (_pendingReceived.isNotEmpty) ...[
            SizedBox(height: 20),
            _friendSectionHeader('DEMANDES REÇUES', _pendingReceived.length,
                AppColors.neonOrange),
            SizedBox(height: 8),
            ..._pendingReceived.map((req) => _receivedRequestCard(req)),
          ],

          // Demandes envoyées en attente
          if (_pendingSent
              .where((s) => s['status'] == 'pending')
              .isNotEmpty) ...[
            SizedBox(height: 20),
            _friendSectionHeader(
                'DEMANDES ENVOYÉES',
                _pendingSent.where((s) => s['status'] == 'pending').length,
                AppColors.neonBlue),
            SizedBox(height: 8),
            ..._pendingSent
                .where((s) => s['status'] == 'pending')
                .map((s) => _sentRequestCard(s)),
          ],

          // Mes amis
          SizedBox(height: 20),
          _friendSectionHeader(
              'MES AMIS', _friends.length, AppColors.neonGreen),
          SizedBox(height: 8),
          if (_friends.isEmpty)
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.people_outline,
                      size: 40,
                      color: AppColors.textMuted.withValues(alpha: 0.3)),
                  SizedBox(height: 8),
                  Text('Aucun ami pour le moment',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13)),
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
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: rank.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                req.fromUsername.isNotEmpty
                    ? req.fromUsername[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: rank.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
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
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Row(children: [
                  Icon(rank.icon, size: 12, color: rank.color),
                  SizedBox(width: 4),
                  Text('${rank.label} • ${req.fromXp} XP',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
                  final ok =
                      await provider.acceptFriendRequest(req.id, req.fromId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? '${req.fromUsername} ajouté en ami !'
                          : 'Erreur'),
                      backgroundColor:
                          ok ? AppColors.neonGreen : AppColors.neonRed,
                    ));
                    _loadFriends();
                  }
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.neonGreen.withValues(alpha: 0.4)),
                  ),
                  child:
                      Icon(Icons.check, color: AppColors.neonGreen, size: 18),
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
                    border: Border.all(
                        color: AppColors.neonRed.withValues(alpha: 0.4)),
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
    final date =
        DateTime.tryParse(req['created_at'] as String? ?? '') ?? DateTime.now();
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                    color: AppColors.neonBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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
                style: TextStyle(
                    color: AppColors.neonYellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: friend.rank.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: friend.rank.color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                friend.username.isNotEmpty
                    ? friend.username[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: friend.rank.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.username,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Row(children: [
                  Icon(friend.rank.icon, size: 12, color: friend.rank.color),
                  SizedBox(width: 4),
                  Text('${friend.rank.label} • ${friend.xp} XP',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]),
              ],
            ),
          ),
          Icon(Icons.chat_bubble_outline, color: AppColors.neonGreen, size: 18),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // K-PAY – DÉPÔT ET RETRAIT
  // ═══════════════════════════════════════════════════════════

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: AppColors.bettingSoftShadow,
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _operatorSelector({
    required String? selected,
    required void Function(String op) onPick,
  }) {
    Widget tile(String value, String label, Color color) {
      final isSelected = selected == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onPick(value),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
            padding: EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.18)
                  : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : AppColors.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isSelected ? color : AppColors.textMuted,
                ),
                SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: isSelected ? color : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 0),
      child: Row(children: [
        tile('MTN_MONEY', 'MTN', AppColors.neonYellow),
        tile('ORANGE_MONEY', 'Orange', AppColors.neonOrange),
      ]),
    );
  }

  void _showDepositDialog() {
    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? error;
    bool loading = false;
    String? selectedOperator; // 'MTN_MONEY' | 'ORANGE_MONEY'
    bool operatorOverridden = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  color: AppColors.neonGreen, size: 22),
              SizedBox(width: 8),
              Text('Dépôt de FCFA',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rechargez votre compte via Mobile Money/Orange Money',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                SizedBox(height: 16),
                if (error != null) ...[
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(error!,
                        style:
                            TextStyle(color: AppColors.neonRed, fontSize: 12)),
                  ),
                  SizedBox(height: 12),
                ],
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Montant (FCFA)',
                    hintText: '100',
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: AppColors.textPrimary),
                  onChanged: (v) {
                    if (operatorOverridden) return;
                    final op = _kpayService.detectOperator(v);
                    if (op != selectedOperator) {
                      setS(() => selectedOperator = op);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Numéro Mobile Money',
                    hintText: '237658895572',
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.phone, color: AppColors.neonGreen, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                _operatorSelector(
                  selected: selectedOperator,
                  onPick: (op) => setS(() {
                    selectedOperator = op;
                    operatorOverridden = true;
                  }),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppColors.neonBlue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('1 FCFA = 1 coin',
                            style: TextStyle(
                                color: AppColors.neonBlue, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final amountStr = amountCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();

                      if (amountStr.isEmpty || phone.isEmpty) {
                        setS(() => error = 'Veuillez remplir tous les champs');
                        return;
                      }

                      final amount = int.tryParse(amountStr);
                      if (amount == null || amount <= 0) {
                        setS(() => error = 'Montant invalide');
                        return;
                      }

                      if (!_kpayService.validatePhoneNumber(phone)) {
                        setS(() =>
                            error = 'Numéro invalide. Format: 237XXXXXXXXX');
                        return;
                      }

                      if (selectedOperator == null) {
                        setS(() =>
                            error = 'Choisis ton opérateur (MTN ou Orange).');
                        return;
                      }

                      setS(() {
                        loading = true;
                        error = null;
                      });

                      final cleanedPhone = _kpayService.cleanPhoneNumber(phone);
                      final result = await _kpayService.initiateDeposit(
                        payer: cleanedPhone,
                        amount: amount,
                        paymentMethod: selectedOperator!,
                      );

                      if (!ctx.mounted) return;

                      if (result['success'] == true) {
                        Navigator.pop(ctx);

                        // Traitement en arriere-plan : pas d'ecran d'attente.
                        // Le joueur continue a jouer ; il sera notifie (push)
                        // des que le depot est credite cote serveur
                        // (webhook / watcher / cron). Le solde se met a jour
                        // tout seul (realtime + refresh au resume).
                        if (mounted) {
                          _loadTransactions();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Dépôt de $amount FCFA en cours. Valide le paiement sur ton téléphone — tu peux continuer à jouer, on te notifie dès que c\'est crédité.',
                              ),
                              backgroundColor: AppColors.neonBlue,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } else {
                        setS(() {
                          loading = false;
                          error = result['message'] ?? 'Erreur inconnue';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text('Confirmer',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawalDialog() {
    final wallet = context.read<WalletProvider>();
    final currentCoins = wallet.coins;

    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? error;
    bool loading = false;
    String? selectedOperator;
    bool operatorOverridden = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.remove_circle_outline,
                  color: AppColors.neonOrange, size: 22),
              SizedBox(width: 8),
              Text('Retrait de FCFA',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retirez vos FCFA vers Mobile Money/Orange Money',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonYellow.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          size: 16, color: AppColors.neonYellow),
                      SizedBox(width: 8),
                      Text('Solde actuel: $currentCoins FCFA',
                          style: TextStyle(
                              color: AppColors.neonYellow,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                if (error != null) ...[
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(error!,
                        style:
                            TextStyle(color: AppColors.neonRed, fontSize: 12)),
                  ),
                  SizedBox(height: 12),
                ],
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Montant (FCFA)',
                    hintText: 'Max: $currentCoins',
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: AppColors.textPrimary),
                  onChanged: (v) {
                    if (operatorOverridden) return;
                    final op = _kpayService.detectOperator(v);
                    if (op != selectedOperator) {
                      setS(() => selectedOperator = op);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Numéro de réception',
                    hintText: '237658895572',
                    labelStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.phone,
                        color: AppColors.neonOrange, size: 20),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                _operatorSelector(
                  selected: selectedOperator,
                  onPick: (op) => setS(() {
                    selectedOperator = op;
                    operatorOverridden = true;
                  }),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppColors.neonBlue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('1 coin = 1 FCFA',
                            style: TextStyle(
                                color: AppColors.neonBlue, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final amountStr = amountCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();

                      if (amountStr.isEmpty || phone.isEmpty) {
                        setS(() => error = 'Veuillez remplir tous les champs');
                        return;
                      }

                      final amount = int.tryParse(amountStr);
                      if (amount == null || amount <= 0) {
                        setS(() => error = 'Montant invalide');
                        return;
                      }

                      // Lecture FRAICHE du solde via RPC wallet_balance (source de
                      // verite = wallet_ledger). Evite les soldes stale du provider.
                      int freshBalance = currentCoins;
                      try {
                        final r = await Supabase.instance.client
                            .rpc('wallet_balance');
                        if (r is int) {
                          freshBalance = r;
                        } else if (r is num) {
                          freshBalance = r.toInt();
                        }
                        // Sync provider tant qu'on a la valeur fraiche
                        if (mounted) {
                          context
                              .read<WalletProvider>()
                              .updateLocal(freshBalance);
                        }
                      } catch (_) {
                        // En cas d'echec : on retombe sur currentCoins
                        // (et on declenche un refresh complet asynchrone)
                        if (mounted) {
                          unawaited(context.read<WalletProvider>().refresh());
                        }
                      }

                      if (amount > freshBalance) {
                        setS(() => error =
                            'Solde insuffisant (vous avez $freshBalance FCFA)');
                        return;
                      }

                      if (!_kpayService.validatePhoneNumber(phone)) {
                        setS(() =>
                            error = 'Numéro invalide. Format: 237XXXXXXXXX');
                        return;
                      }

                      if (selectedOperator == null) {
                        setS(() =>
                            error = 'Choisis ton opérateur (MTN ou Orange).');
                        return;
                      }

                      setS(() {
                        loading = true;
                        error = null;
                      });

                      // Le service initiateWithdrawal gere :
                      //   1. Le debit atomique via ledger V2
                      //   2. L'appel K-Pay
                      //   3. Le refund auto si K-Pay echoue
                      // Plus de double-debit ici.
                      final cleanedPhone = _kpayService.cleanPhoneNumber(phone);
                      final result = await _kpayService.initiateWithdrawal(
                        receiver: cleanedPhone,
                        amount: amount,
                        paymentMethod: selectedOperator!,
                      );

                      // Sync le wallet provider (le debit a deja modifie user_profiles)
                      if (mounted) {
                        unawaited(context.read<WalletProvider>().refresh());
                      }

                      if (!ctx.mounted) return;

                      if (result['success'] == true) {
                        Navigator.pop(ctx);

                        // Traitement en arriere-plan : pas d'ecran d'attente.
                        // Le solde a deja ete debite ; le joueur continue a
                        // jouer et sera notifie (push) du resultat
                        // (retrait effectue, ou echec + remboursement).
                        if (mounted) {
                          wallet.refresh();
                          _loadTransactions();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Retrait de $amount FCFA en cours. Tu peux continuer à jouer — on te notifie dès qu\'il est traité.',
                              ),
                              backgroundColor: AppColors.neonBlue,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } else {
                        // Le refund est deja gere par KpayService.initiateWithdrawal
                        // (RPC kpay_refund_withdrawal). Pas de re-credit ici
                        // pour eviter le double-remboursement.
                        setS(() {
                          loading = false;
                          error = result['message'] ?? 'Erreur inconnue';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Confirmer',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
