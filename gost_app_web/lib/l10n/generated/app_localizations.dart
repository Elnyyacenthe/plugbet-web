import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr')
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'Plugbet'**
  String get appTitle;

  /// No description provided for @tabMatches.
  ///
  /// In fr, this message translates to:
  /// **'Matchs'**
  String get tabMatches;

  /// No description provided for @tabFantasy.
  ///
  /// In fr, this message translates to:
  /// **'Fantasy'**
  String get tabFantasy;

  /// No description provided for @tabGames.
  ///
  /// In fr, this message translates to:
  /// **'Jeux'**
  String get tabGames;

  /// No description provided for @tabChat.
  ///
  /// In fr, this message translates to:
  /// **'Chat'**
  String get tabChat;

  /// No description provided for @tabProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get tabProfile;

  /// No description provided for @tabSettings.
  ///
  /// In fr, this message translates to:
  /// **'Reglages'**
  String get tabSettings;

  /// No description provided for @commonCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get commonConfirm;

  /// No description provided for @commonClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In fr, this message translates to:
  /// **'Reessayer'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement...'**
  String get commonLoading;

  /// No description provided for @commonError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur'**
  String get commonError;

  /// No description provided for @commonRefresh.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser'**
  String get commonRefresh;

  /// No description provided for @commonDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get commonDelete;

  /// No description provided for @commonCopy.
  ///
  /// In fr, this message translates to:
  /// **'Copier'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In fr, this message translates to:
  /// **'Copie'**
  String get commonCopied;

  /// No description provided for @commonOk.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonSend.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get commonSend;

  /// No description provided for @commonSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get commonSave;

  /// No description provided for @commonSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get commonSearch;

  /// No description provided for @commonYes.
  ///
  /// In fr, this message translates to:
  /// **'Oui'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In fr, this message translates to:
  /// **'Non'**
  String get commonNo;

  /// No description provided for @authWelcome.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue'**
  String get authWelcome;

  /// No description provided for @authSignIn.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get authSignIn;

  /// No description provided for @authSignUp.
  ///
  /// In fr, this message translates to:
  /// **'Creer un compte'**
  String get authSignUp;

  /// No description provided for @authSubmitSignUp.
  ///
  /// In fr, this message translates to:
  /// **'S\'inscrire'**
  String get authSubmitSignUp;

  /// No description provided for @authEmail.
  ///
  /// In fr, this message translates to:
  /// **'Adresse email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get authPassword;

  /// No description provided for @authUsername.
  ///
  /// In fr, this message translates to:
  /// **'Nom d\'utilisateur'**
  String get authUsername;

  /// No description provided for @authForgotPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe oublie ?'**
  String get authForgotPassword;

  /// No description provided for @authAlreadyAccount.
  ///
  /// In fr, this message translates to:
  /// **'Deja un compte ?'**
  String get authAlreadyAccount;

  /// No description provided for @authNoAccount.
  ///
  /// In fr, this message translates to:
  /// **'Pas encore de compte ?'**
  String get authNoAccount;

  /// No description provided for @authSignUpSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Inscrivez-vous pour jouer et gagner des coins'**
  String get authSignUpSubtitle;

  /// No description provided for @authSignInSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous pour acceder au multijoueur'**
  String get authSignInSubtitle;

  /// No description provided for @authBonusCoins.
  ///
  /// In fr, this message translates to:
  /// **'Bonus : 500 coins offerts a l\'inscription !'**
  String get authBonusCoins;

  /// No description provided for @authEmailResetSent.
  ///
  /// In fr, this message translates to:
  /// **'Email de reinitialisation envoye a {email}'**
  String authEmailResetSent(String email);

  /// No description provided for @chatNoConversations.
  ///
  /// In fr, this message translates to:
  /// **'Aucune conversation'**
  String get chatNoConversations;

  /// No description provided for @chatStartConversation.
  ///
  /// In fr, this message translates to:
  /// **'Demarrez une conversation avec un autre utilisateur'**
  String get chatStartConversation;

  /// No description provided for @chatMyStatus.
  ///
  /// In fr, this message translates to:
  /// **'Mon statut'**
  String get chatMyStatus;

  /// No description provided for @chatNewMessage.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau message'**
  String get chatNewMessage;

  /// No description provided for @chatOnline.
  ///
  /// In fr, this message translates to:
  /// **'En ligne'**
  String get chatOnline;

  /// No description provided for @chatOffline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne'**
  String get chatOffline;

  /// No description provided for @chatTyping.
  ///
  /// In fr, this message translates to:
  /// **'en train d\'ecrire...'**
  String get chatTyping;

  /// No description provided for @chatSendFirstMessage.
  ///
  /// In fr, this message translates to:
  /// **'Envoyez le premier message !'**
  String get chatSendFirstMessage;

  /// No description provided for @chatReply.
  ///
  /// In fr, this message translates to:
  /// **'Reponse'**
  String get chatReply;

  /// No description provided for @chatDeleteMessageTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer ce message ?'**
  String get chatDeleteMessageTitle;

  /// No description provided for @chatDeleteMessageConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Cette action est irreversible.'**
  String get chatDeleteMessageConfirm;

  /// No description provided for @chatCannotOpenGallery.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir la galerie'**
  String get chatCannotOpenGallery;

  /// No description provided for @chatCannotOpenCamera.
  ///
  /// In fr, this message translates to:
  /// **'Impossible d\'ouvrir la camera'**
  String get chatCannotOpenCamera;

  /// No description provided for @chatFindPlayers.
  ///
  /// In fr, this message translates to:
  /// **'Trouver des joueurs'**
  String get chatFindPlayers;

  /// No description provided for @walletBalance.
  ///
  /// In fr, this message translates to:
  /// **'Solde'**
  String get walletBalance;

  /// No description provided for @walletCoins.
  ///
  /// In fr, this message translates to:
  /// **'coins'**
  String get walletCoins;

  /// No description provided for @walletInsufficientBalance.
  ///
  /// In fr, this message translates to:
  /// **'Solde insuffisant'**
  String get walletInsufficientBalance;

  /// No description provided for @gameHowToPlay.
  ///
  /// In fr, this message translates to:
  /// **'Comment jouer ?'**
  String get gameHowToPlay;

  /// No description provided for @gameTips.
  ///
  /// In fr, this message translates to:
  /// **'Astuces'**
  String get gameTips;

  /// No description provided for @gameUnderstood.
  ///
  /// In fr, this message translates to:
  /// **'Compris !'**
  String get gameUnderstood;

  /// No description provided for @gameBet.
  ///
  /// In fr, this message translates to:
  /// **'Miser'**
  String get gameBet;

  /// No description provided for @gameCashOut.
  ///
  /// In fr, this message translates to:
  /// **'Cash Out'**
  String get gameCashOut;

  /// No description provided for @gameStart.
  ///
  /// In fr, this message translates to:
  /// **'Commencer'**
  String get gameStart;

  /// No description provided for @matchLive.
  ///
  /// In fr, this message translates to:
  /// **'LIVE'**
  String get matchLive;

  /// No description provided for @matchFinished.
  ///
  /// In fr, this message translates to:
  /// **'TERMINE'**
  String get matchFinished;

  /// No description provided for @matchUpcoming.
  ///
  /// In fr, this message translates to:
  /// **'A VENIR'**
  String get matchUpcoming;

  /// No description provided for @matchNoMatches.
  ///
  /// In fr, this message translates to:
  /// **'Aucun match aujourd\'hui'**
  String get matchNoMatches;

  /// No description provided for @matchNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Match introuvable'**
  String get matchNotFound;

  /// No description provided for @matchMatchday.
  ///
  /// In fr, this message translates to:
  /// **'Journee {day}'**
  String matchMatchday(String day);

  /// No description provided for @matchScore.
  ///
  /// In fr, this message translates to:
  /// **'Score'**
  String get matchScore;

  /// No description provided for @matchHalfTime.
  ///
  /// In fr, this message translates to:
  /// **'MT'**
  String get matchHalfTime;

  /// No description provided for @matchLoadingData.
  ///
  /// In fr, this message translates to:
  /// **'Chargement...'**
  String get matchLoadingData;

  /// No description provided for @matchCannotLoadData.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger les donnees'**
  String get matchCannotLoadData;

  /// No description provided for @matchAssist.
  ///
  /// In fr, this message translates to:
  /// **'Passe'**
  String get matchAssist;

  /// No description provided for @profileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mon Profil'**
  String get profileTitle;

  /// No description provided for @profileLogout.
  ///
  /// In fr, this message translates to:
  /// **'Se deconnecter'**
  String get profileLogout;

  /// No description provided for @profileAnonymous.
  ///
  /// In fr, this message translates to:
  /// **'Vous etes en mode anonyme'**
  String get profileAnonymous;

  /// No description provided for @profileTabInfo.
  ///
  /// In fr, this message translates to:
  /// **'Infos'**
  String get profileTabInfo;

  /// No description provided for @profileTabHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get profileTabHistory;

  /// No description provided for @profileTabFriends.
  ///
  /// In fr, this message translates to:
  /// **'Amis'**
  String get profileTabFriends;

  /// No description provided for @profileNoTransactions.
  ///
  /// In fr, this message translates to:
  /// **'Aucune transaction'**
  String get profileNoTransactions;

  /// No description provided for @profileTransactionsHint.
  ///
  /// In fr, this message translates to:
  /// **'Jouez des parties pour voir l\'historique ici'**
  String get profileTransactionsHint;

  /// No description provided for @profileNoFriends.
  ///
  /// In fr, this message translates to:
  /// **'Aucun ami pour le moment'**
  String get profileNoFriends;

  /// No description provided for @profileAddFriend.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher et ajouter un ami'**
  String get profileAddFriend;

  /// No description provided for @profileSection.
  ///
  /// In fr, this message translates to:
  /// **'COMPTE'**
  String get profileSection;

  /// No description provided for @profileMemberSince.
  ///
  /// In fr, this message translates to:
  /// **'Membre depuis'**
  String get profileMemberSince;

  /// No description provided for @drawerMyProfile.
  ///
  /// In fr, this message translates to:
  /// **'Mon Profil'**
  String get drawerMyProfile;

  /// No description provided for @drawerLeaderboard.
  ///
  /// In fr, this message translates to:
  /// **'Classement'**
  String get drawerLeaderboard;

  /// No description provided for @drawerFavorites.
  ///
  /// In fr, this message translates to:
  /// **'Favoris'**
  String get drawerFavorites;

  /// No description provided for @drawerPrivacy.
  ///
  /// In fr, this message translates to:
  /// **'Confidentialite'**
  String get drawerPrivacy;

  /// No description provided for @drawerContact.
  ///
  /// In fr, this message translates to:
  /// **'Nous contacter'**
  String get drawerContact;

  /// No description provided for @drawerHelp.
  ///
  /// In fr, this message translates to:
  /// **'Aide'**
  String get drawerHelp;

  /// No description provided for @settingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Parametres'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAudio.
  ///
  /// In fr, this message translates to:
  /// **'Audio'**
  String get settingsSectionAudio;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In fr, this message translates to:
  /// **'Apparence'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionGameplay.
  ///
  /// In fr, this message translates to:
  /// **'Gameplay'**
  String get settingsSectionGameplay;

  /// No description provided for @settingsSectionNotifs.
  ///
  /// In fr, this message translates to:
  /// **'Notifications & Social'**
  String get settingsSectionNotifs;

  /// No description provided for @settingsSectionAccessibility.
  ///
  /// In fr, this message translates to:
  /// **'Accessibilite & Confort'**
  String get settingsSectionAccessibility;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In fr, this message translates to:
  /// **'Infos & Support'**
  String get settingsSectionAbout;

  /// No description provided for @settingsLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Langue de l\'application'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Systeme'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageFrench.
  ///
  /// In fr, this message translates to:
  /// **'Francais'**
  String get settingsLanguageFrench;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In fr, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsSoundOn.
  ///
  /// In fr, this message translates to:
  /// **'Sons actives'**
  String get settingsSoundOn;

  /// No description provided for @settingsSoundOnSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Activer ou couper tous les sons'**
  String get settingsSoundOnSubtitle;

  /// No description provided for @settingsSfxVolume.
  ///
  /// In fr, this message translates to:
  /// **'Volume effets sonores'**
  String get settingsSfxVolume;

  /// No description provided for @settingsMusicVolume.
  ///
  /// In fr, this message translates to:
  /// **'Volume musique de fond'**
  String get settingsMusicVolume;

  /// No description provided for @settingsLightMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode clair'**
  String get settingsLightMode;

  /// No description provided for @settingsLightModeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Basculer entre le theme sombre et clair'**
  String get settingsLightModeSubtitle;

  /// No description provided for @settingsAiDifficulty.
  ///
  /// In fr, this message translates to:
  /// **'Difficulte IA'**
  String get settingsAiDifficulty;

  /// No description provided for @settingsAiDifficultySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Checkers & Solitaire'**
  String get settingsAiDifficultySubtitle;

  /// No description provided for @settingsDifficultyEasy.
  ///
  /// In fr, this message translates to:
  /// **'Facile'**
  String get settingsDifficultyEasy;

  /// No description provided for @settingsDifficultyMedium.
  ///
  /// In fr, this message translates to:
  /// **'Moyen'**
  String get settingsDifficultyMedium;

  /// No description provided for @settingsDifficultyHard.
  ///
  /// In fr, this message translates to:
  /// **'Difficile'**
  String get settingsDifficultyHard;

  /// No description provided for @settingsPushNotif.
  ///
  /// In fr, this message translates to:
  /// **'Notifications push'**
  String get settingsPushNotif;

  /// No description provided for @settingsPushNotifSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Invites, tour a jouer, victoire d\'ami'**
  String get settingsPushNotifSubtitle;

  /// No description provided for @settingsNotifSounds.
  ///
  /// In fr, this message translates to:
  /// **'Sons de notification'**
  String get settingsNotifSounds;

  /// No description provided for @settingsGoalAlerts.
  ///
  /// In fr, this message translates to:
  /// **'Alertes buts'**
  String get settingsGoalAlerts;

  /// No description provided for @settingsGoalAlertsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pour vos equipes favorites'**
  String get settingsGoalAlertsSubtitle;

  /// No description provided for @settingsMatchStart.
  ///
  /// In fr, this message translates to:
  /// **'Debut de match'**
  String get settingsMatchStart;

  /// No description provided for @settingsMatchStartSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Coup d\'envoi de vos favoris'**
  String get settingsMatchStartSubtitle;

  /// No description provided for @settingsVibrations.
  ///
  /// In fr, this message translates to:
  /// **'Vibrations'**
  String get settingsVibrations;

  /// No description provided for @settingsVibrationsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Retour haptique global'**
  String get settingsVibrationsSubtitle;

  /// No description provided for @settingsVibrationsEvents.
  ///
  /// In fr, this message translates to:
  /// **'Vibrations sur evenements'**
  String get settingsVibrationsEvents;

  /// No description provided for @settingsVibrationsEventsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'De, capture, Cora, victoire'**
  String get settingsVibrationsEventsSubtitle;

  /// No description provided for @settingsInGameChat.
  ///
  /// In fr, this message translates to:
  /// **'Chat en jeu'**
  String get settingsInGameChat;

  /// No description provided for @settingsInGameChatSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Messagerie pendant les parties multijoueur'**
  String get settingsInGameChatSubtitle;

  /// No description provided for @settingsAutoInvite.
  ///
  /// In fr, this message translates to:
  /// **'Invites automatiques'**
  String get settingsAutoInvite;

  /// No description provided for @settingsAutoInviteSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Proposer amis pour rejoindre la partie'**
  String get settingsAutoInviteSubtitle;

  /// No description provided for @settingsLeftyMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode gaucher'**
  String get settingsLeftyMode;

  /// No description provided for @settingsLeftyModeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Inverser les commandes de glissement'**
  String get settingsLeftyModeSubtitle;

  /// No description provided for @settingsHighContrast.
  ///
  /// In fr, this message translates to:
  /// **'Contraste eleve'**
  String get settingsHighContrast;

  /// No description provided for @settingsHighContrastSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Meilleure lisibilite pour malvoyants'**
  String get settingsHighContrastSubtitle;

  /// No description provided for @settingsLargeText.
  ///
  /// In fr, this message translates to:
  /// **'Texte agrandi'**
  String get settingsLargeText;

  /// No description provided for @settingsLargeTextSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Augmenter la taille du texte dans les menus'**
  String get settingsLargeTextSubtitle;

  /// No description provided for @settingsApplication.
  ///
  /// In fr, this message translates to:
  /// **'Application'**
  String get settingsApplication;

  /// No description provided for @settingsVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsGameRules.
  ///
  /// In fr, this message translates to:
  /// **'Regles des jeux'**
  String get settingsGameRules;

  /// No description provided for @settingsContactSupport.
  ///
  /// In fr, this message translates to:
  /// **'Nous contacter / Support'**
  String get settingsContactSupport;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In fr, this message translates to:
  /// **'Politique de confidentialite'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTerms.
  ///
  /// In fr, this message translates to:
  /// **'Conditions d\'utilisation'**
  String get settingsTerms;

  /// No description provided for @supportTitle.
  ///
  /// In fr, this message translates to:
  /// **'Service Client'**
  String get supportTitle;

  /// No description provided for @supportNewTicket.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau ticket'**
  String get supportNewTicket;

  /// No description provided for @supportCategory.
  ///
  /// In fr, this message translates to:
  /// **'Categorie'**
  String get supportCategory;

  /// No description provided for @supportSubject.
  ///
  /// In fr, this message translates to:
  /// **'Sujet'**
  String get supportSubject;

  /// No description provided for @supportCreate.
  ///
  /// In fr, this message translates to:
  /// **'Creer'**
  String get supportCreate;

  /// No description provided for @supportErrorGeneric.
  ///
  /// In fr, this message translates to:
  /// **'Erreur'**
  String get supportErrorGeneric;

  /// No description provided for @supportNoTickets.
  ///
  /// In fr, this message translates to:
  /// **'Aucun ticket ouvert'**
  String get supportNoTickets;

  /// No description provided for @supportCreateFirstTicket.
  ///
  /// In fr, this message translates to:
  /// **'Creer mon premier ticket'**
  String get supportCreateFirstTicket;

  /// No description provided for @supportPlugbet.
  ///
  /// In fr, this message translates to:
  /// **'Support Plugbet'**
  String get supportPlugbet;

  /// No description provided for @supportTicketClosed.
  ///
  /// In fr, this message translates to:
  /// **'Ticket ferme — impossible d\'envoyer de message.'**
  String get supportTicketClosed;

  /// No description provided for @friendsAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get friendsAdd;

  /// No description provided for @friendsInvitationSent.
  ///
  /// In fr, this message translates to:
  /// **'Invitation envoyee a {username} !'**
  String friendsInvitationSent(String username);

  /// No description provided for @friendsAlready.
  ///
  /// In fr, this message translates to:
  /// **'Deja ami'**
  String get friendsAlready;

  /// No description provided for @friendsPending.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get friendsPending;

  /// No description provided for @friendsFriend.
  ///
  /// In fr, this message translates to:
  /// **'Ami'**
  String get friendsFriend;

  /// No description provided for @friendsSendMessage.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer un message'**
  String get friendsSendMessage;

  /// No description provided for @favoritesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes Favoris'**
  String get favoritesTitle;

  /// No description provided for @statusSendFailed.
  ///
  /// In fr, this message translates to:
  /// **'Echec de l\'envoi du statut'**
  String get statusSendFailed;

  /// No description provided for @newChatTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau message'**
  String get newChatTitle;

  /// No description provided for @newChatOnlyFriends.
  ///
  /// In fr, this message translates to:
  /// **'Seuls vos amis peuvent recevoir des messages'**
  String get newChatOnlyFriends;

  /// No description provided for @newChatAddFromFriends.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez des amis depuis l\'ecran Amis'**
  String get newChatAddFromFriends;

  /// No description provided for @newChatNoFriendsFound.
  ///
  /// In fr, this message translates to:
  /// **'Aucun ami trouve'**
  String get newChatNoFriendsFound;

  /// No description provided for @userProfileNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Profil introuvable'**
  String get userProfileNotFound;

  /// No description provided for @gameStay.
  ///
  /// In fr, this message translates to:
  /// **'Rester'**
  String get gameStay;

  /// No description provided for @gameQuit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get gameQuit;

  /// No description provided for @gameForfeit.
  ///
  /// In fr, this message translates to:
  /// **'Forfait'**
  String get gameForfeit;

  /// No description provided for @gameInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Partie en cours'**
  String get gameInProgress;

  /// No description provided for @gameLeaveQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Quitter la partie ?'**
  String get gameLeaveQuestion;

  /// No description provided for @gameLeaveRoomQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Quitter la salle ?'**
  String get gameLeaveRoomQuestion;

  /// No description provided for @gameInsufficientFunds.
  ///
  /// In fr, this message translates to:
  /// **'Fonds insuffisants'**
  String get gameInsufficientFunds;

  /// No description provided for @gameCodeCopied.
  ///
  /// In fr, this message translates to:
  /// **'Code copie !'**
  String get gameCodeCopied;

  /// No description provided for @gameWaitingRoom.
  ///
  /// In fr, this message translates to:
  /// **'Salle d\'attente'**
  String get gameWaitingRoom;

  /// No description provided for @gameCode.
  ///
  /// In fr, this message translates to:
  /// **'Code'**
  String get gameCode;

  /// No description provided for @gameWaiting.
  ///
  /// In fr, this message translates to:
  /// **'En attente...'**
  String get gameWaiting;

  /// No description provided for @gameCreate.
  ///
  /// In fr, this message translates to:
  /// **'Creer'**
  String get gameCreate;

  /// No description provided for @gameJoin.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre'**
  String get gameJoin;

  /// No description provided for @gameJoinAction.
  ///
  /// In fr, this message translates to:
  /// **'REJOINDRE'**
  String get gameJoinAction;

  /// No description provided for @gameCreateAction.
  ///
  /// In fr, this message translates to:
  /// **'CREER'**
  String get gameCreateAction;

  /// No description provided for @gameGo.
  ///
  /// In fr, this message translates to:
  /// **'GO'**
  String get gameGo;

  /// No description provided for @gamePlayAction.
  ///
  /// In fr, this message translates to:
  /// **'JOUER'**
  String get gamePlayAction;

  /// No description provided for @gameDemo.
  ///
  /// In fr, this message translates to:
  /// **'DEMO'**
  String get gameDemo;

  /// No description provided for @gameDemoMode.
  ///
  /// In fr, this message translates to:
  /// **'MODE DEMO'**
  String get gameDemoMode;

  /// No description provided for @gameNextRound.
  ///
  /// In fr, this message translates to:
  /// **'Prochaine manche dans 5s...'**
  String get gameNextRound;

  /// No description provided for @gameNextFlight.
  ///
  /// In fr, this message translates to:
  /// **'PROCHAIN VOL DANS'**
  String get gameNextFlight;

  /// No description provided for @gameCrashed.
  ///
  /// In fr, this message translates to:
  /// **'CRASHE !'**
  String get gameCrashed;

  /// No description provided for @gameDealer.
  ///
  /// In fr, this message translates to:
  /// **'DEALER'**
  String get gameDealer;

  /// No description provided for @gameYou.
  ///
  /// In fr, this message translates to:
  /// **'TOI'**
  String get gameYou;

  /// No description provided for @gameHit.
  ///
  /// In fr, this message translates to:
  /// **'HIT'**
  String get gameHit;

  /// No description provided for @gameStand.
  ///
  /// In fr, this message translates to:
  /// **'STAND'**
  String get gameStand;

  /// No description provided for @gameDealerPlaying.
  ///
  /// In fr, this message translates to:
  /// **'Le dealer joue...'**
  String get gameDealerPlaying;

  /// No description provided for @gameCreateTable.
  ///
  /// In fr, this message translates to:
  /// **'CREER LA TABLE'**
  String get gameCreateTable;

  /// No description provided for @gameResult.
  ///
  /// In fr, this message translates to:
  /// **'Resultat'**
  String get gameResult;

  /// No description provided for @gamePlayers.
  ///
  /// In fr, this message translates to:
  /// **'Joueurs'**
  String get gamePlayers;

  /// No description provided for @gameBetLabel.
  ///
  /// In fr, this message translates to:
  /// **'Mise'**
  String get gameBetLabel;

  /// No description provided for @gamePot.
  ///
  /// In fr, this message translates to:
  /// **'Pot'**
  String get gamePot;

  /// No description provided for @gameScoreLabel.
  ///
  /// In fr, this message translates to:
  /// **'Score'**
  String get gameScoreLabel;

  /// No description provided for @gameSpinWheel.
  ///
  /// In fr, this message translates to:
  /// **'LANCER LA ROUE'**
  String get gameSpinWheel;

  /// No description provided for @gameExactNumber.
  ///
  /// In fr, this message translates to:
  /// **'N° exact'**
  String get gameExactNumber;

  /// No description provided for @gameBetButton.
  ///
  /// In fr, this message translates to:
  /// **'MISER'**
  String get gameBetButton;

  /// No description provided for @gameLobby.
  ///
  /// In fr, this message translates to:
  /// **'Lobby'**
  String get gameLobby;

  /// No description provided for @gameVs.
  ///
  /// In fr, this message translates to:
  /// **'VS'**
  String get gameVs;

  /// No description provided for @gameBack.
  ///
  /// In fr, this message translates to:
  /// **'RETOUR'**
  String get gameBack;

  /// No description provided for @gameRoomNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Room introuvable ou fonds insuffisants'**
  String get gameRoomNotFound;

  /// No description provided for @gamePublicRooms.
  ///
  /// In fr, this message translates to:
  /// **'Rooms publiques'**
  String get gamePublicRooms;

  /// No description provided for @gameNoRoomsAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Aucune room disponible'**
  String get gameNoRoomsAvailable;

  /// No description provided for @gameCreateRoomPrompt.
  ///
  /// In fr, this message translates to:
  /// **'Creez une room pour commencer !'**
  String get gameCreateRoomPrompt;

  /// No description provided for @gameRoomJoinFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de rejoindre (fonds insuffisants ?)'**
  String get gameRoomJoinFailed;

  /// No description provided for @gameCreateRoom.
  ///
  /// In fr, this message translates to:
  /// **'Creer une partie'**
  String get gameCreateRoom;

  /// No description provided for @gameRoomCodeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Code de la room'**
  String get gameRoomCodeTitle;

  /// No description provided for @gameConnectRequired.
  ///
  /// In fr, this message translates to:
  /// **'Connexion requise'**
  String get gameConnectRequired;

  /// No description provided for @gameConnectToPlay.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous pour jouer'**
  String get gameConnectToPlay;

  /// No description provided for @gameHello.
  ///
  /// In fr, this message translates to:
  /// **'Bonjour, {username}'**
  String gameHello(String username);

  /// No description provided for @gameCoinflipTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pile ou Face'**
  String get gameCoinflipTitle;

  /// No description provided for @gameShareCodeHint.
  ///
  /// In fr, this message translates to:
  /// **'Partage ce code a ton adversaire'**
  String get gameShareCodeHint;

  /// No description provided for @gameStartDuel.
  ///
  /// In fr, this message translates to:
  /// **'LANCER LE DUEL'**
  String get gameStartDuel;

  /// No description provided for @gameDuel.
  ///
  /// In fr, this message translates to:
  /// **'DUEL'**
  String get gameDuel;

  /// No description provided for @gameYouChose.
  ///
  /// In fr, this message translates to:
  /// **'Tu as choisi'**
  String get gameYouChose;

  /// No description provided for @gameInactivityKicked.
  ///
  /// In fr, this message translates to:
  /// **'Trop d\'inactivite – tu as ete exclu de la partie'**
  String get gameInactivityKicked;

  /// No description provided for @fantasyConnectTitle.
  ///
  /// In fr, this message translates to:
  /// **'Connecter mon equipe FPL'**
  String get fantasyConnectTitle;

  /// No description provided for @fantasyEntryIdHelp.
  ///
  /// In fr, this message translates to:
  /// **'Ou trouver mon Entry ID ?'**
  String get fantasyEntryIdHelp;

  /// No description provided for @fantasyEntryIdLabel.
  ///
  /// In fr, this message translates to:
  /// **'Entry ID FPL'**
  String get fantasyEntryIdLabel;

  /// No description provided for @fantasyConnect.
  ///
  /// In fr, this message translates to:
  /// **'Connecter'**
  String get fantasyConnect;

  /// No description provided for @fantasyDisconnect.
  ///
  /// In fr, this message translates to:
  /// **'Se deconnecter'**
  String get fantasyDisconnect;

  /// No description provided for @fantasyCreateTeam.
  ///
  /// In fr, this message translates to:
  /// **'Creer mon equipe'**
  String get fantasyCreateTeam;

  /// No description provided for @fantasyTeamCreated.
  ///
  /// In fr, this message translates to:
  /// **'Equipe creee ! Ajoutez vos joueurs via Transferts.'**
  String get fantasyTeamCreated;

  /// No description provided for @fantasyUnexpectedError.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur inattendue s\'est produite.'**
  String get fantasyUnexpectedError;

  /// No description provided for @fantasyLoadingPlayers.
  ///
  /// In fr, this message translates to:
  /// **'Chargement des donnees joueurs...'**
  String get fantasyLoadingPlayers;

  /// No description provided for @fantasyNoPlayerSelected.
  ///
  /// In fr, this message translates to:
  /// **'Aucun joueur selectionne'**
  String get fantasyNoPlayerSelected;

  /// No description provided for @fantasyAddPlayers.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter des joueurs'**
  String get fantasyAddPlayers;

  /// No description provided for @fantasyJoinLeague.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre une ligue'**
  String get fantasyJoinLeague;

  /// No description provided for @fantasyLeagueJoined.
  ///
  /// In fr, this message translates to:
  /// **'Ligue rejointe !'**
  String get fantasyLeagueJoined;

  /// No description provided for @fantasyLeagueCreated.
  ///
  /// In fr, this message translates to:
  /// **'Ligue creee !'**
  String get fantasyLeagueCreated;

  /// No description provided for @fantasyAddPlayersFirst.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez des joueurs a votre equipe d\'abord.'**
  String get fantasyAddPlayersFirst;

  /// No description provided for @fantasyCreateLeague.
  ///
  /// In fr, this message translates to:
  /// **'Creer une ligue'**
  String get fantasyCreateLeague;

  /// No description provided for @fantasyJoinByCode.
  ///
  /// In fr, this message translates to:
  /// **'Rejoindre par code'**
  String get fantasyJoinByCode;

  /// No description provided for @fantasyMyLeagues.
  ///
  /// In fr, this message translates to:
  /// **'Mes Ligues'**
  String get fantasyMyLeagues;

  /// No description provided for @fantasyPublicLeague.
  ///
  /// In fr, this message translates to:
  /// **'Ligue publique'**
  String get fantasyPublicLeague;

  /// No description provided for @fantasyNoLeagues.
  ///
  /// In fr, this message translates to:
  /// **'Aucune ligue pour l\'instant'**
  String get fantasyNoLeagues;

  /// No description provided for @fantasyNoLeaguesHint.
  ///
  /// In fr, this message translates to:
  /// **'Creez ou rejoignez une ligue\npour affronter vos amis'**
  String get fantasyNoLeaguesHint;

  /// No description provided for @fantasyNoMembers.
  ///
  /// In fr, this message translates to:
  /// **'Aucun membre dans cette ligue.'**
  String get fantasyNoMembers;

  /// No description provided for @fantasyChooseFormation.
  ///
  /// In fr, this message translates to:
  /// **'Choisir la formation'**
  String get fantasyChooseFormation;

  /// No description provided for @fantasyNoSubstitute.
  ///
  /// In fr, this message translates to:
  /// **'Aucun remplacant disponible.'**
  String get fantasyNoSubstitute;

  /// No description provided for @fantasyNeed11.
  ///
  /// In fr, this message translates to:
  /// **'Il faut exactement 11 titulaires pour sauvegarder.'**
  String get fantasyNeed11;

  /// No description provided for @fantasyCoachTitle.
  ///
  /// In fr, this message translates to:
  /// **'Coach · Mon Equipe'**
  String get fantasyCoachTitle;

  /// No description provided for @fantasySave.
  ///
  /// In fr, this message translates to:
  /// **'Sauver'**
  String get fantasySave;

  /// No description provided for @fantasyChange.
  ///
  /// In fr, this message translates to:
  /// **'Changer'**
  String get fantasyChange;

  /// No description provided for @fantasyTapToSwap.
  ///
  /// In fr, this message translates to:
  /// **'Tap = permuter'**
  String get fantasyTapToSwap;

  /// No description provided for @fantasyChips.
  ///
  /// In fr, this message translates to:
  /// **'CHIPS'**
  String get fantasyChips;

  /// No description provided for @fantasyUsed.
  ///
  /// In fr, this message translates to:
  /// **'UTILISE'**
  String get fantasyUsed;

  /// No description provided for @fantasyActivate.
  ///
  /// In fr, this message translates to:
  /// **'ACTIVER'**
  String get fantasyActivate;

  /// No description provided for @fantasyTacticalSummary.
  ///
  /// In fr, this message translates to:
  /// **'RESUME TACTIQUE'**
  String get fantasyTacticalSummary;

  /// No description provided for @fantasyTransfersTitle.
  ///
  /// In fr, this message translates to:
  /// **'Transferts'**
  String get fantasyTransfersTitle;

  /// No description provided for @fantasyBudget.
  ///
  /// In fr, this message translates to:
  /// **'Budget'**
  String get fantasyBudget;

  /// No description provided for @ludoQuitQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Quitter la partie ?'**
  String get ludoQuitQuestion;

  /// No description provided for @ludoForfeitMessage.
  ///
  /// In fr, this message translates to:
  /// **'Tu perdras la partie par forfait.'**
  String get ludoForfeitMessage;

  /// No description provided for @ludoTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ludo'**
  String get ludoTitle;

  /// No description provided for @ludoWaitingPlayers.
  ///
  /// In fr, this message translates to:
  /// **'En attente des joueurs...'**
  String get ludoWaitingPlayers;

  /// No description provided for @chatMessageDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Message supprime'**
  String get chatMessageDeleted;

  /// No description provided for @chatYesterday.
  ///
  /// In fr, this message translates to:
  /// **'Hier'**
  String get chatYesterday;

  /// No description provided for @chatToday.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get chatToday;

  /// No description provided for @aviatorSlot.
  ///
  /// In fr, this message translates to:
  /// **'MISE {slot}'**
  String aviatorSlot(String slot);

  /// No description provided for @aviatorAuto.
  ///
  /// In fr, this message translates to:
  /// **'Auto'**
  String get aviatorAuto;

  /// No description provided for @aviatorManual.
  ///
  /// In fr, this message translates to:
  /// **'Manuel'**
  String get aviatorManual;

  /// No description provided for @aviatorInFlight.
  ///
  /// In fr, this message translates to:
  /// **'EN VOL...'**
  String get aviatorInFlight;

  /// No description provided for @aviatorBetBeforeTakeoff.
  ///
  /// In fr, this message translates to:
  /// **'✈  Misez avant le prochain decollage'**
  String get aviatorBetBeforeTakeoff;

  /// No description provided for @aviatorBetPlaced.
  ///
  /// In fr, this message translates to:
  /// **'Mise placee'**
  String get aviatorBetPlaced;

  /// No description provided for @aviatorInsufficientBalance.
  ///
  /// In fr, this message translates to:
  /// **'Solde insuffisant ou mise invalide.'**
  String get aviatorInsufficientBalance;

  /// No description provided for @aviatorBetButton.
  ///
  /// In fr, this message translates to:
  /// **'MISER'**
  String get aviatorBetButton;

  /// No description provided for @aviatorCashout.
  ///
  /// In fr, this message translates to:
  /// **'CASHOUT'**
  String get aviatorCashout;

  /// No description provided for @homeTabLive.
  ///
  /// In fr, this message translates to:
  /// **'LIVE'**
  String get homeTabLive;

  /// No description provided for @homeTabYesterday.
  ///
  /// In fr, this message translates to:
  /// **'HIER'**
  String get homeTabYesterday;

  /// No description provided for @homeTabToday.
  ///
  /// In fr, this message translates to:
  /// **'AUJOURD\'HUI'**
  String get homeTabToday;

  /// No description provided for @homeTabTomorrow.
  ///
  /// In fr, this message translates to:
  /// **'DEMAIN'**
  String get homeTabTomorrow;

  /// No description provided for @splashInit.
  ///
  /// In fr, this message translates to:
  /// **'Initialisation...'**
  String get splashInit;

  /// No description provided for @splashConnecting.
  ///
  /// In fr, this message translates to:
  /// **'Connexion aux serveurs...'**
  String get splashConnecting;

  /// No description provided for @splashLoadingMatches.
  ///
  /// In fr, this message translates to:
  /// **'Chargement des matchs...'**
  String get splashLoadingMatches;

  /// No description provided for @splashLoading.
  ///
  /// In fr, this message translates to:
  /// **'Preparation de l\'interface...'**
  String get splashLoading;

  /// No description provided for @splashAlmostReady.
  ///
  /// In fr, this message translates to:
  /// **'Presque pret...'**
  String get splashAlmostReady;

  /// No description provided for @authQuickAccount.
  ///
  /// In fr, this message translates to:
  /// **'Compte rapide'**
  String get authQuickAccount;

  /// No description provided for @authQuickAccountSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pseudo + mot de passe, sans email'**
  String get authQuickAccountSubtitle;

  /// No description provided for @authGoogleSignIn.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec Google'**
  String get authGoogleSignIn;

  /// No description provided for @authPhoneSignIn.
  ///
  /// In fr, this message translates to:
  /// **'Continuer avec telephone'**
  String get authPhoneSignIn;

  /// No description provided for @authPhoneNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numero de telephone'**
  String get authPhoneNumber;

  /// No description provided for @authPhoneHint.
  ///
  /// In fr, this message translates to:
  /// **'+237 6XX XXX XXX'**
  String get authPhoneHint;

  /// No description provided for @authSendOtp.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le code'**
  String get authSendOtp;

  /// No description provided for @authOtpSent.
  ///
  /// In fr, this message translates to:
  /// **'Code envoye a {phone}'**
  String authOtpSent(String phone);

  /// No description provided for @authOtpCode.
  ///
  /// In fr, this message translates to:
  /// **'Code de verification'**
  String get authOtpCode;

  /// No description provided for @authVerify.
  ///
  /// In fr, this message translates to:
  /// **'Verifier'**
  String get authVerify;

  /// No description provided for @authOr.
  ///
  /// In fr, this message translates to:
  /// **'ou'**
  String get authOr;

  /// No description provided for @authAccountCreated.
  ///
  /// In fr, this message translates to:
  /// **'Compte cree avec succes !'**
  String get authAccountCreated;

  /// No description provided for @authLoginSuccess.
  ///
  /// In fr, this message translates to:
  /// **'Connexion reussie !'**
  String get authLoginSuccess;

  /// No description provided for @authEnterEmailFirst.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre email d\'abord'**
  String get authEnterEmailFirst;

  /// No description provided for @authPseudo.
  ///
  /// In fr, this message translates to:
  /// **'Pseudo'**
  String get authPseudo;

  /// No description provided for @profileUpgradeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Passer en compte officiel'**
  String get profileUpgradeTitle;

  /// No description provided for @profileUpgradeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Remplissez vos infos pour securiser votre compte'**
  String get profileUpgradeSubtitle;

  /// No description provided for @profileFullName.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get profileFullName;

  /// No description provided for @profilePhoneNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numero de telephone'**
  String get profilePhoneNumber;

  /// No description provided for @profileUpgradeSuccess.
  ///
  /// In fr, this message translates to:
  /// **'Compte officiel active !'**
  String get profileUpgradeSuccess;

  /// No description provided for @profileOfficialBadge.
  ///
  /// In fr, this message translates to:
  /// **'OFFICIEL'**
  String get profileOfficialBadge;

  /// No description provided for @profileQuickBadge.
  ///
  /// In fr, this message translates to:
  /// **'RAPIDE'**
  String get profileQuickBadge;

  /// No description provided for @profileChangePassword.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le mot de passe'**
  String get profileChangePassword;

  /// No description provided for @profileCurrentPassword.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe actuel'**
  String get profileCurrentPassword;

  /// No description provided for @profileNewPassword.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau mot de passe'**
  String get profileNewPassword;

  /// No description provided for @profileConfirmPassword.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le nouveau mot de passe'**
  String get profileConfirmPassword;

  /// No description provided for @profilePasswordChanged.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe modifie avec succes !'**
  String get profilePasswordChanged;

  /// No description provided for @profilePasswordMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Les mots de passe ne correspondent pas'**
  String get profilePasswordMismatch;

  /// No description provided for @profilePasswordTooShort.
  ///
  /// In fr, this message translates to:
  /// **'Minimum 6 caracteres'**
  String get profilePasswordTooShort;

  /// No description provided for @profileChange.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get profileChange;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise a jour disponible'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableMessage.
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle version de l\'application est prete a etre installee. Voulez-vous redemarrer maintenant ?'**
  String get updateAvailableMessage;

  /// No description provided for @updateRestartNow.
  ///
  /// In fr, this message translates to:
  /// **'Redemarrer'**
  String get updateRestartNow;

  /// No description provided for @updateLater.
  ///
  /// In fr, this message translates to:
  /// **'Plus tard'**
  String get updateLater;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
