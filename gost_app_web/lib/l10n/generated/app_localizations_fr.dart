// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Plugbet';

  @override
  String get tabMatches => 'Matchs';

  @override
  String get tabFantasy => 'Fantasy';

  @override
  String get tabGames => 'Jeux';

  @override
  String get tabChat => 'Chat';

  @override
  String get tabProfile => 'Profil';

  @override
  String get tabSettings => 'Reglages';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonConfirm => 'Confirmer';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonRetry => 'Reessayer';

  @override
  String get commonLoading => 'Chargement...';

  @override
  String get commonError => 'Erreur';

  @override
  String get commonRefresh => 'Actualiser';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonCopy => 'Copier';

  @override
  String get commonCopied => 'Copie';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSend => 'Envoyer';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonSearch => 'Rechercher';

  @override
  String get commonYes => 'Oui';

  @override
  String get commonNo => 'Non';

  @override
  String get authWelcome => 'Bienvenue';

  @override
  String get authSignIn => 'Se connecter';

  @override
  String get authSignUp => 'Creer un compte';

  @override
  String get authSubmitSignUp => 'S\'inscrire';

  @override
  String get authEmail => 'Adresse email';

  @override
  String get authPassword => 'Mot de passe';

  @override
  String get authUsername => 'Nom d\'utilisateur';

  @override
  String get authForgotPassword => 'Mot de passe oublie ?';

  @override
  String get authAlreadyAccount => 'Deja un compte ?';

  @override
  String get authNoAccount => 'Pas encore de compte ?';

  @override
  String get authSignUpSubtitle =>
      'Inscrivez-vous pour jouer et gagner des coins';

  @override
  String get authSignInSubtitle => 'Connectez-vous pour acceder au multijoueur';

  @override
  String get authBonusCoins => 'Bonus : 500 coins offerts a l\'inscription !';

  @override
  String authEmailResetSent(String email) {
    return 'Email de reinitialisation envoye a $email';
  }

  @override
  String get chatNoConversations => 'Aucune conversation';

  @override
  String get chatStartConversation =>
      'Demarrez une conversation avec un autre utilisateur';

  @override
  String get chatMyStatus => 'Mon statut';

  @override
  String get chatNewMessage => 'Nouveau message';

  @override
  String get chatOnline => 'En ligne';

  @override
  String get chatOffline => 'Hors ligne';

  @override
  String get chatTyping => 'en train d\'ecrire...';

  @override
  String get chatSendFirstMessage => 'Envoyez le premier message !';

  @override
  String get chatReply => 'Reponse';

  @override
  String get chatDeleteMessageTitle => 'Supprimer ce message ?';

  @override
  String get chatDeleteMessageConfirm => 'Cette action est irreversible.';

  @override
  String get chatCannotOpenGallery => 'Impossible d\'ouvrir la galerie';

  @override
  String get chatCannotOpenCamera => 'Impossible d\'ouvrir la camera';

  @override
  String get chatFindPlayers => 'Trouver des joueurs';

  @override
  String get walletBalance => 'Solde';

  @override
  String get walletCoins => 'coins';

  @override
  String get walletInsufficientBalance => 'Solde insuffisant';

  @override
  String get gameHowToPlay => 'Comment jouer ?';

  @override
  String get gameTips => 'Astuces';

  @override
  String get gameUnderstood => 'Compris !';

  @override
  String get gameBet => 'Miser';

  @override
  String get gameCashOut => 'Cash Out';

  @override
  String get gameStart => 'Commencer';

  @override
  String get matchLive => 'LIVE';

  @override
  String get matchFinished => 'TERMINE';

  @override
  String get matchUpcoming => 'A VENIR';

  @override
  String get matchNoMatches => 'Aucun match aujourd\'hui';

  @override
  String get matchNotFound => 'Match introuvable';

  @override
  String matchMatchday(String day) {
    return 'Journee $day';
  }

  @override
  String get matchScore => 'Score';

  @override
  String get matchHalfTime => 'MT';

  @override
  String get matchLoadingData => 'Chargement...';

  @override
  String get matchCannotLoadData => 'Impossible de charger les donnees';

  @override
  String get matchAssist => 'Passe';

  @override
  String get profileTitle => 'Mon Profil';

  @override
  String get profileLogout => 'Se deconnecter';

  @override
  String get profileAnonymous => 'Vous etes en mode anonyme';

  @override
  String get profileTabInfo => 'Infos';

  @override
  String get profileTabHistory => 'Historique';

  @override
  String get profileTabFriends => 'Amis';

  @override
  String get profileNoTransactions => 'Aucune transaction';

  @override
  String get profileTransactionsHint =>
      'Jouez des parties pour voir l\'historique ici';

  @override
  String get profileNoFriends => 'Aucun ami pour le moment';

  @override
  String get profileAddFriend => 'Rechercher et ajouter un ami';

  @override
  String get profileSection => 'COMPTE';

  @override
  String get profileMemberSince => 'Membre depuis';

  @override
  String get drawerMyProfile => 'Mon Profil';

  @override
  String get drawerLeaderboard => 'Classement';

  @override
  String get drawerFavorites => 'Favoris';

  @override
  String get drawerPrivacy => 'Confidentialite';

  @override
  String get drawerContact => 'Nous contacter';

  @override
  String get drawerHelp => 'Aide';

  @override
  String get settingsTitle => 'Parametres';

  @override
  String get settingsSectionAudio => 'Audio';

  @override
  String get settingsSectionAppearance => 'Apparence';

  @override
  String get settingsSectionGameplay => 'Gameplay';

  @override
  String get settingsSectionNotifs => 'Notifications & Social';

  @override
  String get settingsSectionAccessibility => 'Accessibilite & Confort';

  @override
  String get settingsSectionAbout => 'Infos & Support';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSubtitle => 'Langue de l\'application';

  @override
  String get settingsLanguageSystem => 'Systeme';

  @override
  String get settingsLanguageFrench => 'Francais';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsSoundOn => 'Sons actives';

  @override
  String get settingsSoundOnSubtitle => 'Activer ou couper tous les sons';

  @override
  String get settingsSfxVolume => 'Volume effets sonores';

  @override
  String get settingsMusicVolume => 'Volume musique de fond';

  @override
  String get settingsLightMode => 'Mode clair';

  @override
  String get settingsLightModeSubtitle =>
      'Basculer entre le theme sombre et clair';

  @override
  String get settingsAiDifficulty => 'Difficulte IA';

  @override
  String get settingsAiDifficultySubtitle => 'Checkers & Solitaire';

  @override
  String get settingsDifficultyEasy => 'Facile';

  @override
  String get settingsDifficultyMedium => 'Moyen';

  @override
  String get settingsDifficultyHard => 'Difficile';

  @override
  String get settingsPushNotif => 'Notifications push';

  @override
  String get settingsPushNotifSubtitle =>
      'Invites, tour a jouer, victoire d\'ami';

  @override
  String get settingsNotifSounds => 'Sons de notification';

  @override
  String get settingsGoalAlerts => 'Alertes buts';

  @override
  String get settingsGoalAlertsSubtitle => 'Pour vos equipes favorites';

  @override
  String get settingsMatchStart => 'Debut de match';

  @override
  String get settingsMatchStartSubtitle => 'Coup d\'envoi de vos favoris';

  @override
  String get settingsVibrations => 'Vibrations';

  @override
  String get settingsVibrationsSubtitle => 'Retour haptique global';

  @override
  String get settingsVibrationsEvents => 'Vibrations sur evenements';

  @override
  String get settingsVibrationsEventsSubtitle => 'De, capture, Cora, victoire';

  @override
  String get settingsInGameChat => 'Chat en jeu';

  @override
  String get settingsInGameChatSubtitle =>
      'Messagerie pendant les parties multijoueur';

  @override
  String get settingsAutoInvite => 'Invites automatiques';

  @override
  String get settingsAutoInviteSubtitle =>
      'Proposer amis pour rejoindre la partie';

  @override
  String get settingsLeftyMode => 'Mode gaucher';

  @override
  String get settingsLeftyModeSubtitle =>
      'Inverser les commandes de glissement';

  @override
  String get settingsHighContrast => 'Contraste eleve';

  @override
  String get settingsHighContrastSubtitle =>
      'Meilleure lisibilite pour malvoyants';

  @override
  String get settingsLargeText => 'Texte agrandi';

  @override
  String get settingsLargeTextSubtitle =>
      'Augmenter la taille du texte dans les menus';

  @override
  String get settingsApplication => 'Application';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsGameRules => 'Regles des jeux';

  @override
  String get settingsContactSupport => 'Nous contacter / Support';

  @override
  String get settingsPrivacyPolicy => 'Politique de confidentialite';

  @override
  String get settingsTerms => 'Conditions d\'utilisation';

  @override
  String get supportTitle => 'Service Client';

  @override
  String get supportNewTicket => 'Nouveau ticket';

  @override
  String get supportCategory => 'Categorie';

  @override
  String get supportSubject => 'Sujet';

  @override
  String get supportCreate => 'Creer';

  @override
  String get supportErrorGeneric => 'Erreur';

  @override
  String get supportNoTickets => 'Aucun ticket ouvert';

  @override
  String get supportCreateFirstTicket => 'Creer mon premier ticket';

  @override
  String get supportPlugbet => 'Support Plugbet';

  @override
  String get supportTicketClosed =>
      'Ticket ferme — impossible d\'envoyer de message.';

  @override
  String get friendsAdd => 'Ajouter';

  @override
  String friendsInvitationSent(String username) {
    return 'Invitation envoyee a $username !';
  }

  @override
  String get friendsAlready => 'Deja ami';

  @override
  String get friendsPending => 'En attente';

  @override
  String get friendsFriend => 'Ami';

  @override
  String get friendsSendMessage => 'Envoyer un message';

  @override
  String get favoritesTitle => 'Mes Favoris';

  @override
  String get statusSendFailed => 'Echec de l\'envoi du statut';

  @override
  String get newChatTitle => 'Nouveau message';

  @override
  String get newChatOnlyFriends =>
      'Seuls vos amis peuvent recevoir des messages';

  @override
  String get newChatAddFromFriends => 'Ajoutez des amis depuis l\'ecran Amis';

  @override
  String get newChatNoFriendsFound => 'Aucun ami trouve';

  @override
  String get userProfileNotFound => 'Profil introuvable';

  @override
  String get gameStay => 'Rester';

  @override
  String get gameQuit => 'Quitter';

  @override
  String get gameForfeit => 'Forfait';

  @override
  String get gameInProgress => 'Partie en cours';

  @override
  String get gameLeaveQuestion => 'Quitter la partie ?';

  @override
  String get gameLeaveRoomQuestion => 'Quitter la salle ?';

  @override
  String get gameInsufficientFunds => 'Fonds insuffisants';

  @override
  String get gameCodeCopied => 'Code copie !';

  @override
  String get gameWaitingRoom => 'Salle d\'attente';

  @override
  String get gameCode => 'Code';

  @override
  String get gameWaiting => 'En attente...';

  @override
  String get gameCreate => 'Creer';

  @override
  String get gameJoin => 'Rejoindre';

  @override
  String get gameJoinAction => 'REJOINDRE';

  @override
  String get gameCreateAction => 'CREER';

  @override
  String get gameGo => 'GO';

  @override
  String get gamePlayAction => 'JOUER';

  @override
  String get gameDemo => 'DEMO';

  @override
  String get gameDemoMode => 'MODE DEMO';

  @override
  String get gameNextRound => 'Prochaine manche dans 5s...';

  @override
  String get gameNextFlight => 'PROCHAIN VOL DANS';

  @override
  String get gameCrashed => 'CRASHE !';

  @override
  String get gameDealer => 'DEALER';

  @override
  String get gameYou => 'TOI';

  @override
  String get gameHit => 'HIT';

  @override
  String get gameStand => 'STAND';

  @override
  String get gameDealerPlaying => 'Le dealer joue...';

  @override
  String get gameCreateTable => 'CREER LA TABLE';

  @override
  String get gameResult => 'Resultat';

  @override
  String get gamePlayers => 'Joueurs';

  @override
  String get gameBetLabel => 'Mise';

  @override
  String get gamePot => 'Pot';

  @override
  String get gameScoreLabel => 'Score';

  @override
  String get gameSpinWheel => 'LANCER LA ROUE';

  @override
  String get gameExactNumber => 'N° exact';

  @override
  String get gameBetButton => 'MISER';

  @override
  String get gameLobby => 'Lobby';

  @override
  String get gameVs => 'VS';

  @override
  String get gameBack => 'RETOUR';

  @override
  String get gameRoomNotFound => 'Room introuvable ou fonds insuffisants';

  @override
  String get gamePublicRooms => 'Rooms publiques';

  @override
  String get gameNoRoomsAvailable => 'Aucune room disponible';

  @override
  String get gameCreateRoomPrompt => 'Creez une room pour commencer !';

  @override
  String get gameRoomJoinFailed =>
      'Impossible de rejoindre (fonds insuffisants ?)';

  @override
  String get gameCreateRoom => 'Creer une partie';

  @override
  String get gameRoomCodeTitle => 'Code de la room';

  @override
  String get gameConnectRequired => 'Connexion requise';

  @override
  String get gameConnectToPlay => 'Connectez-vous pour jouer';

  @override
  String gameHello(String username) {
    return 'Bonjour, $username';
  }

  @override
  String get gameCoinflipTitle => 'Pile ou Face';

  @override
  String get gameShareCodeHint => 'Partage ce code a ton adversaire';

  @override
  String get gameStartDuel => 'LANCER LE DUEL';

  @override
  String get gameDuel => 'DUEL';

  @override
  String get gameYouChose => 'Tu as choisi';

  @override
  String get gameInactivityKicked =>
      'Trop d\'inactivite – tu as ete exclu de la partie';

  @override
  String get fantasyConnectTitle => 'Connecter mon equipe FPL';

  @override
  String get fantasyEntryIdHelp => 'Ou trouver mon Entry ID ?';

  @override
  String get fantasyEntryIdLabel => 'Entry ID FPL';

  @override
  String get fantasyConnect => 'Connecter';

  @override
  String get fantasyDisconnect => 'Se deconnecter';

  @override
  String get fantasyCreateTeam => 'Creer mon equipe';

  @override
  String get fantasyTeamCreated =>
      'Equipe creee ! Ajoutez vos joueurs via Transferts.';

  @override
  String get fantasyUnexpectedError => 'Une erreur inattendue s\'est produite.';

  @override
  String get fantasyLoadingPlayers => 'Chargement des donnees joueurs...';

  @override
  String get fantasyNoPlayerSelected => 'Aucun joueur selectionne';

  @override
  String get fantasyAddPlayers => 'Ajouter des joueurs';

  @override
  String get fantasyJoinLeague => 'Rejoindre une ligue';

  @override
  String get fantasyLeagueJoined => 'Ligue rejointe !';

  @override
  String get fantasyLeagueCreated => 'Ligue creee !';

  @override
  String get fantasyAddPlayersFirst =>
      'Ajoutez des joueurs a votre equipe d\'abord.';

  @override
  String get fantasyCreateLeague => 'Creer une ligue';

  @override
  String get fantasyJoinByCode => 'Rejoindre par code';

  @override
  String get fantasyMyLeagues => 'Mes Ligues';

  @override
  String get fantasyPublicLeague => 'Ligue publique';

  @override
  String get fantasyNoLeagues => 'Aucune ligue pour l\'instant';

  @override
  String get fantasyNoLeaguesHint =>
      'Creez ou rejoignez une ligue\npour affronter vos amis';

  @override
  String get fantasyNoMembers => 'Aucun membre dans cette ligue.';

  @override
  String get fantasyChooseFormation => 'Choisir la formation';

  @override
  String get fantasyNoSubstitute => 'Aucun remplacant disponible.';

  @override
  String get fantasyNeed11 =>
      'Il faut exactement 11 titulaires pour sauvegarder.';

  @override
  String get fantasyCoachTitle => 'Coach · Mon Equipe';

  @override
  String get fantasySave => 'Sauver';

  @override
  String get fantasyChange => 'Changer';

  @override
  String get fantasyTapToSwap => 'Tap = permuter';

  @override
  String get fantasyChips => 'CHIPS';

  @override
  String get fantasyUsed => 'UTILISE';

  @override
  String get fantasyActivate => 'ACTIVER';

  @override
  String get fantasyTacticalSummary => 'RESUME TACTIQUE';

  @override
  String get fantasyTransfersTitle => 'Transferts';

  @override
  String get fantasyBudget => 'Budget';

  @override
  String get ludoQuitQuestion => 'Quitter la partie ?';

  @override
  String get ludoForfeitMessage => 'Tu perdras la partie par forfait.';

  @override
  String get ludoTitle => 'Ludo';

  @override
  String get ludoWaitingPlayers => 'En attente des joueurs...';

  @override
  String get chatMessageDeleted => 'Message supprime';

  @override
  String get chatYesterday => 'Hier';

  @override
  String get chatToday => 'Aujourd\'hui';

  @override
  String aviatorSlot(String slot) {
    return 'MISE $slot';
  }

  @override
  String get aviatorAuto => 'Auto';

  @override
  String get aviatorManual => 'Manuel';

  @override
  String get aviatorInFlight => 'EN VOL...';

  @override
  String get aviatorBetBeforeTakeoff => '✈  Misez avant le prochain decollage';

  @override
  String get aviatorBetPlaced => 'Mise placee';

  @override
  String get aviatorInsufficientBalance =>
      'Solde insuffisant ou mise invalide.';

  @override
  String get aviatorBetButton => 'MISER';

  @override
  String get aviatorCashout => 'CASHOUT';

  @override
  String get homeTabLive => 'LIVE';

  @override
  String get homeTabYesterday => 'HIER';

  @override
  String get homeTabToday => 'AUJOURD\'HUI';

  @override
  String get homeTabTomorrow => 'DEMAIN';

  @override
  String get splashInit => 'Initialisation...';

  @override
  String get splashConnecting => 'Connexion aux serveurs...';

  @override
  String get splashLoadingMatches => 'Chargement des matchs...';

  @override
  String get splashLoading => 'Preparation de l\'interface...';

  @override
  String get splashAlmostReady => 'Presque pret...';

  @override
  String get authQuickAccount => 'Compte rapide';

  @override
  String get authQuickAccountSubtitle => 'Pseudo + mot de passe, sans email';

  @override
  String get authGoogleSignIn => 'Continuer avec Google';

  @override
  String get authPhoneSignIn => 'Continuer avec telephone';

  @override
  String get authPhoneNumber => 'Numero de telephone';

  @override
  String get authPhoneHint => '+237 6XX XXX XXX';

  @override
  String get authSendOtp => 'Envoyer le code';

  @override
  String authOtpSent(String phone) {
    return 'Code envoye a $phone';
  }

  @override
  String get authOtpCode => 'Code de verification';

  @override
  String get authVerify => 'Verifier';

  @override
  String get authOr => 'ou';

  @override
  String get authAccountCreated => 'Compte cree avec succes !';

  @override
  String get authLoginSuccess => 'Connexion reussie !';

  @override
  String get authEnterEmailFirst => 'Entrez votre email d\'abord';

  @override
  String get authPseudo => 'Pseudo';

  @override
  String get profileUpgradeTitle => 'Passer en compte officiel';

  @override
  String get profileUpgradeSubtitle =>
      'Remplissez vos infos pour securiser votre compte';

  @override
  String get profileFullName => 'Nom complet';

  @override
  String get profilePhoneNumber => 'Numero de telephone';

  @override
  String get profileUpgradeSuccess => 'Compte officiel active !';

  @override
  String get profileOfficialBadge => 'OFFICIEL';

  @override
  String get profileQuickBadge => 'RAPIDE';

  @override
  String get profileChangePassword => 'Modifier le mot de passe';

  @override
  String get profileCurrentPassword => 'Mot de passe actuel';

  @override
  String get profileNewPassword => 'Nouveau mot de passe';

  @override
  String get profileConfirmPassword => 'Confirmer le nouveau mot de passe';

  @override
  String get profilePasswordChanged => 'Mot de passe modifie avec succes !';

  @override
  String get profilePasswordMismatch =>
      'Les mots de passe ne correspondent pas';

  @override
  String get profilePasswordTooShort => 'Minimum 6 caracteres';

  @override
  String get profileChange => 'Modifier';

  @override
  String get updateAvailableTitle => 'Mise a jour disponible';

  @override
  String get updateAvailableMessage =>
      'Une nouvelle version de l\'application est prete a etre installee. Voulez-vous redemarrer maintenant ?';

  @override
  String get updateRestartNow => 'Redemarrer';

  @override
  String get updateLater => 'Plus tard';
}
