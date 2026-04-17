// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Plugbet';

  @override
  String get tabMatches => 'Matches';

  @override
  String get tabFantasy => 'Fantasy';

  @override
  String get tabGames => 'Games';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabProfile => 'Profile';

  @override
  String get tabSettings => 'Settings';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonError => 'Error';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSend => 'Send';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get authWelcome => 'Welcome';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignUp => 'Create account';

  @override
  String get authSubmitSignUp => 'Sign up';

  @override
  String get authEmail => 'Email address';

  @override
  String get authPassword => 'Password';

  @override
  String get authUsername => 'Username';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authAlreadyAccount => 'Already have an account?';

  @override
  String get authNoAccount => 'No account yet?';

  @override
  String get authSignUpSubtitle => 'Sign up to play and earn coins';

  @override
  String get authSignInSubtitle => 'Sign in to access multiplayer';

  @override
  String get authBonusCoins => 'Bonus: 500 coins on sign up!';

  @override
  String authEmailResetSent(String email) {
    return 'Reset email sent to $email';
  }

  @override
  String get chatNoConversations => 'No conversations';

  @override
  String get chatStartConversation => 'Start a conversation with another user';

  @override
  String get chatMyStatus => 'My status';

  @override
  String get chatNewMessage => 'New message';

  @override
  String get chatOnline => 'Online';

  @override
  String get chatOffline => 'Offline';

  @override
  String get chatTyping => 'typing...';

  @override
  String get chatSendFirstMessage => 'Send the first message!';

  @override
  String get chatReply => 'Reply';

  @override
  String get chatDeleteMessageTitle => 'Delete this message?';

  @override
  String get chatDeleteMessageConfirm => 'This action is irreversible.';

  @override
  String get chatCannotOpenGallery => 'Cannot open gallery';

  @override
  String get chatCannotOpenCamera => 'Cannot open camera';

  @override
  String get chatFindPlayers => 'Find players';

  @override
  String get walletBalance => 'Balance';

  @override
  String get walletCoins => 'coins';

  @override
  String get walletInsufficientBalance => 'Insufficient balance';

  @override
  String get gameHowToPlay => 'How to play?';

  @override
  String get gameTips => 'Tips';

  @override
  String get gameUnderstood => 'Got it!';

  @override
  String get gameBet => 'Bet';

  @override
  String get gameCashOut => 'Cash Out';

  @override
  String get gameStart => 'Start';

  @override
  String get matchLive => 'LIVE';

  @override
  String get matchFinished => 'FINISHED';

  @override
  String get matchUpcoming => 'UPCOMING';

  @override
  String get matchNoMatches => 'No matches today';

  @override
  String get matchNotFound => 'Match not found';

  @override
  String matchMatchday(String day) {
    return 'Matchday $day';
  }

  @override
  String get matchScore => 'Score';

  @override
  String get matchHalfTime => 'HT';

  @override
  String get matchLoadingData => 'Loading...';

  @override
  String get matchCannotLoadData => 'Unable to load data';

  @override
  String get matchAssist => 'Assist';

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileLogout => 'Log out';

  @override
  String get profileAnonymous => 'You are in anonymous mode';

  @override
  String get profileTabInfo => 'Info';

  @override
  String get profileTabHistory => 'History';

  @override
  String get profileTabFriends => 'Friends';

  @override
  String get profileNoTransactions => 'No transactions';

  @override
  String get profileTransactionsHint => 'Play games to see your history here';

  @override
  String get profileNoFriends => 'No friends yet';

  @override
  String get profileAddFriend => 'Search and add a friend';

  @override
  String get profileSection => 'ACCOUNT';

  @override
  String get profileMemberSince => 'Member since';

  @override
  String get drawerMyProfile => 'My Profile';

  @override
  String get drawerLeaderboard => 'Leaderboard';

  @override
  String get drawerFavorites => 'Favorites';

  @override
  String get drawerPrivacy => 'Privacy';

  @override
  String get drawerContact => 'Contact us';

  @override
  String get drawerHelp => 'Help';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAudio => 'Audio';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsSectionGameplay => 'Gameplay';

  @override
  String get settingsSectionNotifs => 'Notifications & Social';

  @override
  String get settingsSectionAccessibility => 'Accessibility & Comfort';

  @override
  String get settingsSectionAbout => 'Info & Support';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'App language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageFrench => 'Francais';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsSoundOn => 'Sound on';

  @override
  String get settingsSoundOnSubtitle => 'Enable or mute all sounds';

  @override
  String get settingsSfxVolume => 'Sound effects volume';

  @override
  String get settingsMusicVolume => 'Background music volume';

  @override
  String get settingsLightMode => 'Light mode';

  @override
  String get settingsLightModeSubtitle => 'Switch between dark and light theme';

  @override
  String get settingsAiDifficulty => 'AI difficulty';

  @override
  String get settingsAiDifficultySubtitle => 'Checkers & Solitaire';

  @override
  String get settingsDifficultyEasy => 'Easy';

  @override
  String get settingsDifficultyMedium => 'Medium';

  @override
  String get settingsDifficultyHard => 'Hard';

  @override
  String get settingsPushNotif => 'Push notifications';

  @override
  String get settingsPushNotifSubtitle => 'Invites, turn to play, friend wins';

  @override
  String get settingsNotifSounds => 'Notification sounds';

  @override
  String get settingsGoalAlerts => 'Goal alerts';

  @override
  String get settingsGoalAlertsSubtitle => 'For your favorite teams';

  @override
  String get settingsMatchStart => 'Match start';

  @override
  String get settingsMatchStartSubtitle => 'Kick-off of your favorites';

  @override
  String get settingsVibrations => 'Vibrations';

  @override
  String get settingsVibrationsSubtitle => 'Global haptic feedback';

  @override
  String get settingsVibrationsEvents => 'Event vibrations';

  @override
  String get settingsVibrationsEventsSubtitle => 'Dice, capture, Cora, victory';

  @override
  String get settingsInGameChat => 'In-game chat';

  @override
  String get settingsInGameChatSubtitle => 'Messaging during multiplayer games';

  @override
  String get settingsAutoInvite => 'Auto-invites';

  @override
  String get settingsAutoInviteSubtitle => 'Suggest friends to join the game';

  @override
  String get settingsLeftyMode => 'Left-handed mode';

  @override
  String get settingsLeftyModeSubtitle => 'Reverse swipe controls';

  @override
  String get settingsHighContrast => 'High contrast';

  @override
  String get settingsHighContrastSubtitle =>
      'Better readability for visually impaired';

  @override
  String get settingsLargeText => 'Large text';

  @override
  String get settingsLargeTextSubtitle => 'Increase text size in menus';

  @override
  String get settingsApplication => 'Application';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsGameRules => 'Game rules';

  @override
  String get settingsContactSupport => 'Contact us / Support';

  @override
  String get settingsPrivacyPolicy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of use';

  @override
  String get supportTitle => 'Customer Service';

  @override
  String get supportNewTicket => 'New ticket';

  @override
  String get supportCategory => 'Category';

  @override
  String get supportSubject => 'Subject';

  @override
  String get supportCreate => 'Create';

  @override
  String get supportErrorGeneric => 'Error';

  @override
  String get supportNoTickets => 'No open tickets';

  @override
  String get supportCreateFirstTicket => 'Create my first ticket';

  @override
  String get supportPlugbet => 'Plugbet Support';

  @override
  String get supportTicketClosed => 'Ticket closed — cannot send messages.';

  @override
  String get friendsAdd => 'Add';

  @override
  String friendsInvitationSent(String username) {
    return 'Invitation sent to $username!';
  }

  @override
  String get friendsAlready => 'Already friends';

  @override
  String get friendsPending => 'Pending';

  @override
  String get friendsFriend => 'Friend';

  @override
  String get friendsSendMessage => 'Send a message';

  @override
  String get favoritesTitle => 'My Favorites';

  @override
  String get statusSendFailed => 'Failed to send status';

  @override
  String get newChatTitle => 'New message';

  @override
  String get newChatOnlyFriends => 'Only your friends can receive messages';

  @override
  String get newChatAddFromFriends => 'Add friends from the Friends screen';

  @override
  String get newChatNoFriendsFound => 'No friends found';

  @override
  String get userProfileNotFound => 'Profile not found';

  @override
  String get gameStay => 'Stay';

  @override
  String get gameQuit => 'Leave';

  @override
  String get gameForfeit => 'Forfeit';

  @override
  String get gameInProgress => 'Game in progress';

  @override
  String get gameLeaveQuestion => 'Leave the game?';

  @override
  String get gameLeaveRoomQuestion => 'Leave the room?';

  @override
  String get gameInsufficientFunds => 'Insufficient funds';

  @override
  String get gameCodeCopied => 'Code copied!';

  @override
  String get gameWaitingRoom => 'Waiting room';

  @override
  String get gameCode => 'Code';

  @override
  String get gameWaiting => 'Waiting...';

  @override
  String get gameCreate => 'Create';

  @override
  String get gameJoin => 'Join';

  @override
  String get gameJoinAction => 'JOIN';

  @override
  String get gameCreateAction => 'CREATE';

  @override
  String get gameGo => 'GO';

  @override
  String get gamePlayAction => 'PLAY';

  @override
  String get gameDemo => 'DEMO';

  @override
  String get gameDemoMode => 'DEMO MODE';

  @override
  String get gameNextRound => 'Next round in 5s...';

  @override
  String get gameNextFlight => 'NEXT FLIGHT IN';

  @override
  String get gameCrashed => 'CRASHED!';

  @override
  String get gameDealer => 'DEALER';

  @override
  String get gameYou => 'YOU';

  @override
  String get gameHit => 'HIT';

  @override
  String get gameStand => 'STAND';

  @override
  String get gameDealerPlaying => 'Dealer is playing...';

  @override
  String get gameCreateTable => 'CREATE TABLE';

  @override
  String get gameResult => 'Result';

  @override
  String get gamePlayers => 'Players';

  @override
  String get gameBetLabel => 'Bet';

  @override
  String get gamePot => 'Pot';

  @override
  String get gameScoreLabel => 'Score';

  @override
  String get gameSpinWheel => 'SPIN THE WHEEL';

  @override
  String get gameExactNumber => 'Exact no.';

  @override
  String get gameBetButton => 'BET';

  @override
  String get gameLobby => 'Lobby';

  @override
  String get gameVs => 'VS';

  @override
  String get gameBack => 'BACK';

  @override
  String get gameRoomNotFound => 'Room not found or insufficient funds';

  @override
  String get gamePublicRooms => 'Public rooms';

  @override
  String get gameNoRoomsAvailable => 'No rooms available';

  @override
  String get gameCreateRoomPrompt => 'Create a room to start!';

  @override
  String get gameRoomJoinFailed => 'Cannot join (insufficient funds?)';

  @override
  String get gameCreateRoom => 'Create a game';

  @override
  String get gameRoomCodeTitle => 'Room code';

  @override
  String get gameConnectRequired => 'Login required';

  @override
  String get gameConnectToPlay => 'Log in to play';

  @override
  String gameHello(String username) {
    return 'Hello, $username';
  }

  @override
  String get gameCoinflipTitle => 'Coin Flip';

  @override
  String get gameShareCodeHint => 'Share this code with your opponent';

  @override
  String get gameStartDuel => 'START THE DUEL';

  @override
  String get gameDuel => 'DUEL';

  @override
  String get gameYouChose => 'You chose';

  @override
  String get gameInactivityKicked =>
      'Too much inactivity – you were kicked from the game';

  @override
  String get fantasyConnectTitle => 'Connect my FPL team';

  @override
  String get fantasyEntryIdHelp => 'Where do I find my Entry ID?';

  @override
  String get fantasyEntryIdLabel => 'FPL Entry ID';

  @override
  String get fantasyConnect => 'Connect';

  @override
  String get fantasyDisconnect => 'Disconnect';

  @override
  String get fantasyCreateTeam => 'Create my team';

  @override
  String get fantasyTeamCreated => 'Team created! Add players via Transfers.';

  @override
  String get fantasyUnexpectedError => 'An unexpected error occurred.';

  @override
  String get fantasyLoadingPlayers => 'Loading player data...';

  @override
  String get fantasyNoPlayerSelected => 'No player selected';

  @override
  String get fantasyAddPlayers => 'Add players';

  @override
  String get fantasyJoinLeague => 'Join a league';

  @override
  String get fantasyLeagueJoined => 'League joined!';

  @override
  String get fantasyLeagueCreated => 'League created!';

  @override
  String get fantasyAddPlayersFirst => 'Add players to your team first.';

  @override
  String get fantasyCreateLeague => 'Create a league';

  @override
  String get fantasyJoinByCode => 'Join by code';

  @override
  String get fantasyMyLeagues => 'My Leagues';

  @override
  String get fantasyPublicLeague => 'Public league';

  @override
  String get fantasyNoLeagues => 'No leagues yet';

  @override
  String get fantasyNoLeaguesHint =>
      'Create or join a league\nto challenge your friends';

  @override
  String get fantasyNoMembers => 'No members in this league.';

  @override
  String get fantasyChooseFormation => 'Choose formation';

  @override
  String get fantasyNoSubstitute => 'No substitute available.';

  @override
  String get fantasyNeed11 => 'Exactly 11 starters needed to save.';

  @override
  String get fantasyCoachTitle => 'Coach · My Team';

  @override
  String get fantasySave => 'Save';

  @override
  String get fantasyChange => 'Change';

  @override
  String get fantasyTapToSwap => 'Tap = swap';

  @override
  String get fantasyChips => 'CHIPS';

  @override
  String get fantasyUsed => 'USED';

  @override
  String get fantasyActivate => 'ACTIVATE';

  @override
  String get fantasyTacticalSummary => 'TACTICAL SUMMARY';

  @override
  String get fantasyTransfersTitle => 'Transfers';

  @override
  String get fantasyBudget => 'Budget';

  @override
  String get ludoQuitQuestion => 'Leave the game?';

  @override
  String get ludoForfeitMessage => 'You will lose by forfeit.';

  @override
  String get ludoTitle => 'Ludo';

  @override
  String get ludoWaitingPlayers => 'Waiting for players...';

  @override
  String get chatMessageDeleted => 'Message deleted';

  @override
  String get chatYesterday => 'Yesterday';

  @override
  String get chatToday => 'Today';

  @override
  String aviatorSlot(String slot) {
    return 'BET $slot';
  }

  @override
  String get aviatorAuto => 'Auto';

  @override
  String get aviatorManual => 'Manual';

  @override
  String get aviatorInFlight => 'IN FLIGHT...';

  @override
  String get aviatorBetBeforeTakeoff => '✈  Place your bet before next takeoff';

  @override
  String get aviatorBetPlaced => 'Bet placed';

  @override
  String get aviatorInsufficientBalance =>
      'Insufficient balance or invalid bet.';

  @override
  String get aviatorBetButton => 'BET';

  @override
  String get aviatorCashout => 'CASHOUT';

  @override
  String get homeTabLive => 'LIVE';

  @override
  String get homeTabYesterday => 'YESTERDAY';

  @override
  String get homeTabToday => 'TODAY';

  @override
  String get homeTabTomorrow => 'TOMORROW';

  @override
  String get splashInit => 'Initializing...';

  @override
  String get splashConnecting => 'Connecting to servers...';

  @override
  String get splashLoadingMatches => 'Loading matches...';

  @override
  String get splashLoading => 'Preparing interface...';

  @override
  String get splashAlmostReady => 'Almost ready...';

  @override
  String get authQuickAccount => 'Quick account';

  @override
  String get authQuickAccountSubtitle => 'Username + password, no email needed';

  @override
  String get authGoogleSignIn => 'Continue with Google';

  @override
  String get authPhoneSignIn => 'Continue with phone';

  @override
  String get authPhoneNumber => 'Phone number';

  @override
  String get authPhoneHint => '+237 6XX XXX XXX';

  @override
  String get authSendOtp => 'Send code';

  @override
  String authOtpSent(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get authOtpCode => 'Verification code';

  @override
  String get authVerify => 'Verify';

  @override
  String get authOr => 'or';

  @override
  String get authAccountCreated => 'Account created successfully!';

  @override
  String get authLoginSuccess => 'Login successful!';

  @override
  String get authEnterEmailFirst => 'Enter your email first';

  @override
  String get authPseudo => 'Username';

  @override
  String get profileUpgradeTitle => 'Upgrade to official account';

  @override
  String get profileUpgradeSubtitle =>
      'Fill in your info to secure your account';

  @override
  String get profileFullName => 'Full name';

  @override
  String get profilePhoneNumber => 'Phone number';

  @override
  String get profileUpgradeSuccess => 'Official account activated!';

  @override
  String get profileOfficialBadge => 'OFFICIAL';

  @override
  String get profileQuickBadge => 'QUICK';

  @override
  String get profileChangePassword => 'Change password';

  @override
  String get profileCurrentPassword => 'Current password';

  @override
  String get profileNewPassword => 'New password';

  @override
  String get profileConfirmPassword => 'Confirm new password';

  @override
  String get profilePasswordChanged => 'Password changed successfully!';

  @override
  String get profilePasswordMismatch => 'Passwords do not match';

  @override
  String get profilePasswordTooShort => 'Minimum 6 characters';

  @override
  String get profileChange => 'Change';

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String get updateAvailableMessage =>
      'A new version of the app is ready to install. Restart now?';

  @override
  String get updateRestartNow => 'Restart';

  @override
  String get updateLater => 'Later';
}
