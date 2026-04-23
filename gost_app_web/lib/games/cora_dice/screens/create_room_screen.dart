// ============================================================
// CORA DICE - Écran création de room
// Choix du nombre de joueurs, mise personnalisée, vérification du solde
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../services/cora_service.dart';
import '../../../ludo/models/ludo_models.dart';

class CreateCoraRoomScreen extends StatefulWidget {
  const CreateCoraRoomScreen({super.key});

  @override
  State<CreateCoraRoomScreen> createState() => _CreateCoraRoomScreenState();
}

class _CreateCoraRoomScreenState extends State<CreateCoraRoomScreen> {
  final CoraService _service = CoraService();
  final _supabase = Supabase.instance.client;
  final TextEditingController _betController = TextEditingController(text: '200');

  int _playerCount = 2;
  double _betAmount = 200;
  bool _isPrivate = false;
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  UserProfile? _userProfile;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _betController.addListener(_onBetInputChanged);
  }

  @override
  void dispose() {
    _betController.dispose();
    super.dispose();
  }

  void _onBetInputChanged() {
    final text = _betController.text;
    if (text.isEmpty) return;

    final value = int.tryParse(text);
    if (value != null && value >= 50) {
      final coins = _userProfile?.coins ?? 0;
      final maxBet = coins < 1000 ? coins : 1000;
      final clampedValue = value > maxBet ? maxBet : value;

      if (_betAmount != clampedValue.toDouble()) {
        setState(() {
          _betAmount = clampedValue.toDouble();
        });
      }
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _errorMessage = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _errorMessage = 'Vous devez être connecté pour créer une partie';
          _isLoadingProfile = false;
        });
        return;
      }

      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        // Créer un profil par défaut
        final newProfile = {
          'id': userId,
          'username': _supabase.auth.currentUser?.email?.split('@')[0] ?? 'Joueur',
          'coins': 500,
          'games_played': 0,
          'games_won': 0,
        };
        await _supabase.from('user_profiles').upsert(newProfile);
        setState(() {
          _userProfile = UserProfile.fromJson(newProfile);
          _isLoadingProfile = false;
        });
      } else {
        setState(() {
          _userProfile = UserProfile.fromJson(response);
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du chargement du profil: $e';
        _isLoadingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.gameCreateRoom),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _isLoadingProfile
            ? Center(
                child: CircularProgressIndicator(color: AppColors.neonGreen),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              color: AppColors.neonRed, size: 64),
                          SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.neonGreen,
                              foregroundColor: AppColors.bgDark,
                            ),
                            child: Text('Retour'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Solde actuel
                        _buildBalanceCard(),
                        SizedBox(height: isSmallScreen ? 16 : 24),

                        // Nombre de joueurs
                        _buildPlayerCountSelector(isSmallScreen),
                        SizedBox(height: isSmallScreen ? 16 : 24),

                        // Slider de mise
                        _buildBetSlider(isSmallScreen),
                        SizedBox(height: isSmallScreen ? 16 : 20),

                        // Mode privé
                        _buildPrivateModeSwitch(),
                        SizedBox(height: isSmallScreen ? 16 : 24),

                        // Règles (compactes si petit écran)
                        if (!isSmallScreen) _buildRulesCard(),
                        if (!isSmallScreen)
                          SizedBox(height: isSmallScreen ? 16 : 24),

                        // Bouton créer
                        _buildCreateButton(),
                        SizedBox(height: 16),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final coins = _userProfile?.coins ?? 0;
    final hasEnoughCoins = coins >= _betAmount;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.neonBlue.withValues(alpha: 0.2),
            AppColors.neonPurple.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.account_balance_wallet,
                color: AppColors.neonBlue, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Votre solde',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '$coins FCFA',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (!hasEnoughCoins)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.neonRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonRed),
              ),
              child: Text(
                'Solde insuffisant',
                style: TextStyle(
                  color: AppColors.neonRed,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerCountSelector(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nombre de joueurs',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: isSmallScreen ? 8 : 12,
          runSpacing: isSmallScreen ? 8 : 12,
          children: [2, 3, 4, 5, 6].map((count) {
            final selected = _playerCount == count;
            final size = isSmallScreen ? 50.0 : 60.0;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _playerCount = count);
              },
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: selected
                      ? LinearGradient(
                          colors: [AppColors.neonGreen, Color(0xFF2ECC71)],
                        )
                      : null,
                  color: selected ? null : AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.neonGreen : AppColors.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected ? AppColors.bgDark : AppColors.textPrimary,
                      fontSize: isSmallScreen ? 20 : 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBetSlider(bool isSmallScreen) {
    final potTotal = (_betAmount * _playerCount).toInt();
    final coins = _userProfile?.coins ?? 0;
    final maxAffordable = (coins / 1).floor().toDouble();
    final sliderMax = maxAffordable < 1000 ? maxAffordable : 1000.0;

    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.neonYellow.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 20),
              SizedBox(width: 8),
              Text(
                'Mise par joueur',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Champ de saisie manuelle
          TextField(
            controller: _betController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.neonYellow.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.neonYellow.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.neonYellow,
                  width: 2,
                ),
              ),
              suffixText: 'coins',
              suffixStyle: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              hintText: '50 - ${sliderMax.toInt()}',
              hintStyle: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.5),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),

          SizedBox(height: 16),
          Center(
            child: Text(
              'ou utilisez le slider',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.neonYellow,
              inactiveTrackColor: AppColors.divider,
              thumbColor: AppColors.neonYellow,
              overlayColor: AppColors.neonYellow.withValues(alpha: 0.3),
              valueIndicatorColor: AppColors.neonYellow,
              valueIndicatorTextStyle: TextStyle(
                color: AppColors.bgDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Slider(
              value: _betAmount,
              min: 50,
              max: sliderMax < 50 ? 50 : sliderMax,
              divisions: ((sliderMax - 50) / 50).floor(),
              label: '${_betAmount.toInt()}',
              onChanged: (value) {
                setState(() {
                  _betAmount = value;
                  _betController.text = value.toInt().toString();
                });
              },
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '50 FCFA',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
              Text(
                'Pot total : $potTotal FCFA',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: isSmallScreen ? 12 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${sliderMax.toInt()} FCFA',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateModeSwitch() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            _isPrivate ? Icons.lock : Icons.public,
            color: _isPrivate ? Colors.orange : AppColors.neonGreen,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Partie privée',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Accessible uniquement par code',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPrivate,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _isPrivate = v);
            },
            activeColor: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildRulesCard() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.neonBlue, size: 16),
              SizedBox(width: 8),
              Text(
                'Règles Cora',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          _ruleText('• CORA (1+1) : Double pot !'),
          _ruleText('• 7 : Perd automatiquement'),
          _ruleText('• Plus haut total gagne'),
        ],
      ),
    );
  }

  Widget _ruleText(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    final coins = _userProfile?.coins ?? 0;
    final hasEnoughCoins = coins >= _betAmount;
    final canCreate = hasEnoughCoins && !_isLoading;

    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: canCreate ? _createRoom : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: hasEnoughCoins ? AppColors.neonGreen : AppColors.bgElevated,
          foregroundColor: hasEnoughCoins ? AppColors.bgDark : AppColors.textMuted,
          disabledBackgroundColor: AppColors.bgElevated,
          disabledForegroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: hasEnoughCoins ? 8 : 0,
        ),
        child: _isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.bgDark,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasEnoughCoins ? Icons.play_arrow_rounded : Icons.lock,
                    size: 26,
                  ),
                  SizedBox(width: 8),
                  Text(
                    hasEnoughCoins ? 'Créer la partie' : 'Solde insuffisant',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _createRoom() async {
    final coins = _userProfile?.coins ?? 0;
    if (coins < _betAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Solde insuffisant ! Vous avez $coins FCFA, il faut ${_betAmount.toInt()} FCFA.',
          ),
          backgroundColor: AppColors.neonRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _service.createRoom(
        playerCount: _playerCount,
        isPrivate: _isPrivate,
        betAmount: _betAmount.toInt(),
      );

      if (result != null && mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context, result['room_id']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : ${e.toString()}'),
            backgroundColor: AppColors.neonRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
