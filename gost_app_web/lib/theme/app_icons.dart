// ============================================================
// Plugbet – Table d'icônes
// ============================================================
// Point d'entrée UNIQUE pour toutes les icônes de l'application.
//
// Avant : 220 icônes Material pleines, 151 en `_rounded`, 16 en
// `_outlined`, plus des emojis en dur dans une dizaine de fichiers.
// Trois graisses mélangées, aucune cohérence de trait.
//
// Maintenant : Phosphor, graisse `Regular` par défaut, `Fill` pour les
// états actifs (onglet sélectionné, favori coché). Les écrans ne
// référencent JAMAIS `PhosphorIcons*` directement — ils passent par
// les noms sémantiques ci-dessous. Changer de jeu d'icônes ne coûte
// alors qu'une passe sur ce fichier.
//
// ⚠️ On dépend du fork `phosphoricons_flutter` et non du paquet
// officiel `phosphor_flutter` : ce dernier étend `IconData`, devenue
// une classe `final` en Dart 3, et ne compile plus.
// ============================================================

import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class AppIcons {
  const AppIcons._();

  // ── Navigation principale ────────────────────────────────────
  static const IconData bets = PhosphorIconsRegular.lightning;
  static const IconData betsActive = PhosphorIconsFill.lightning;
  static const IconData games = PhosphorIconsRegular.gameController;
  static const IconData gamesActive = PhosphorIconsFill.gameController;
  static const IconData chat = PhosphorIconsRegular.chatCircleDots;
  static const IconData chatActive = PhosphorIconsFill.chatCircleDots;
  static const IconData profile = PhosphorIconsRegular.user;
  static const IconData profileActive = PhosphorIconsFill.user;
  static const IconData settings = PhosphorIconsRegular.gearSix;
  static const IconData settingsActive = PhosphorIconsFill.gearSix;
  static const IconData menu = PhosphorIconsRegular.list;

  // ── Direction & flèches ──────────────────────────────────────
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData backIos = PhosphorIconsRegular.caretLeft;
  static const IconData forward = PhosphorIconsRegular.arrowRight;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronUp = PhosphorIconsRegular.caretUp;
  static const IconData up = PhosphorIconsRegular.arrowUp;
  static const IconData down = PhosphorIconsRegular.arrowDown;
  static const IconData swap = PhosphorIconsRegular.arrowsLeftRight;
  static const IconData reply = PhosphorIconsRegular.arrowBendUpLeft;
  static const IconData replay = PhosphorIconsRegular.arrowCounterClockwise;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;

  // ── Actions ──────────────────────────────────────────────────
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData addCircle = PhosphorIconsRegular.plusCircle;
  static const IconData remove = PhosphorIconsRegular.minus;
  static const IconData removeCircle = PhosphorIconsRegular.minusCircle;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData delete = PhosphorIconsRegular.trash;
  static const IconData copy = PhosphorIconsRegular.copy;
  static const IconData paste = PhosphorIconsRegular.clipboardText;
  static const IconData share = PhosphorIconsRegular.shareNetwork;
  static const IconData send = PhosphorIconsRegular.paperPlaneTilt;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData cancel = PhosphorIconsRegular.xCircle;
  static const IconData more = PhosphorIconsRegular.dotsThreeVertical;
  static const IconData attach = PhosphorIconsRegular.paperclip;
  static const IconData emoji = PhosphorIconsRegular.smiley;
  static const IconData tag = PhosphorIconsRegular.tag;
  static const IconData qrCode = PhosphorIconsRegular.qrCode;

  // ── États & validation ───────────────────────────────────────
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData checkAll = PhosphorIconsRegular.checks;
  static const IconData checkCircle = PhosphorIconsRegular.checkCircle;
  static const IconData checkCircleFilled = PhosphorIconsFill.checkCircle;
  static const IconData dot = PhosphorIconsFill.circle;
  static const IconData radioOn = PhosphorIconsRegular.radioButton;
  static const IconData radioOff = PhosphorIconsRegular.circle;
  static const IconData blocked = PhosphorIconsRegular.prohibit;
  static const IconData warning = PhosphorIconsRegular.warningCircle;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData help = PhosphorIconsRegular.question;
  static const IconData bug = PhosphorIconsRegular.bug;
  static const IconData pending = PhosphorIconsRegular.hourglass;

  // ── Compte & sécurité ────────────────────────────────────────
  static const IconData login = PhosphorIconsRegular.signIn;
  static const IconData logout = PhosphorIconsRegular.signOut;
  static const IconData lock = PhosphorIconsRegular.lockSimple;
  static const IconData eye = PhosphorIconsRegular.eye;
  static const IconData eyeOff = PhosphorIconsRegular.eyeSlash;
  static const IconData verified = PhosphorIconsRegular.shieldCheck;
  static const IconData privacy = PhosphorIconsRegular.shieldStar;
  static const IconData accountManage = PhosphorIconsRegular.userGear;
  static const IconData accessibility = PhosphorIconsRegular.personSimple;

  // ── Social ───────────────────────────────────────────────────
  static const IconData friends = PhosphorIconsRegular.usersThree;
  static const IconData friendAdd = PhosphorIconsRegular.userPlus;
  static const IconData friendRemove = PhosphorIconsRegular.userMinus;
  static const IconData userSearch = PhosphorIconsRegular.userFocus;
  static const IconData support = PhosphorIconsRegular.headset;
  static const IconData mail = PhosphorIconsRegular.envelopeSimple;
  static const IconData at = PhosphorIconsRegular.at;
  static const IconData phone = PhosphorIconsRegular.phone;
  static const IconData notification = PhosphorIconsRegular.bell;

  // ── Argent & portefeuille ────────────────────────────────────
  static const IconData wallet = PhosphorIconsRegular.wallet;
  static const IconData coins = PhosphorIconsRegular.coins;
  static const IconData coinsFilled = PhosphorIconsFill.coins;
  static const IconData card = PhosphorIconsRegular.creditCard;
  static const IconData savings = PhosphorIconsRegular.piggyBank;
  static const IconData receipt = PhosphorIconsRegular.receipt;
  static const IconData gift = PhosphorIconsRegular.gift;

  // ── Sport ────────────────────────────────────────────────────
  static const IconData football = PhosphorIconsRegular.soccerBall;
  static const IconData footballFilled = PhosphorIconsFill.soccerBall;
  static const IconData basketball = PhosphorIconsRegular.basketball;
  static const IconData tennis = PhosphorIconsRegular.tennisBall;
  static const IconData venue = PhosphorIconsRegular.mapPin;

  // Courses virtuelles : voitures et lévriers.
  static const IconData raceCar = PhosphorIconsRegular.car;
  static const IconData greyhound = PhosphorIconsRegular.dog;
  /// Sport indéterminé, dans l'historique des paris.
  static const IconData sportUnknown = PhosphorIconsRegular.trophy;

  // ── Jeux ─────────────────────────────────────────────────────
  static const IconData dice = PhosphorIconsRegular.diceFive;
  static const IconData cards = PhosphorIconsRegular.spade;
  static const IconData target = PhosphorIconsRegular.target;
  static const IconData plane = PhosphorIconsRegular.airplaneTakeoff;
  static const IconData car = PhosphorIconsRegular.car;
  static const IconData gem = PhosphorIconsRegular.diamond;
  static const IconData crown = PhosphorIconsRegular.crown;
  static const IconData sparkle = PhosphorIconsRegular.sparkle;

  // ── Progression & récompenses ────────────────────────────────
  static const IconData trophy = PhosphorIconsRegular.trophy;
  static const IconData trophyFilled = PhosphorIconsFill.trophy;
  static const IconData medal = PhosphorIconsRegular.medal;
  static const IconData premium = PhosphorIconsRegular.certificate;
  static const IconData leaderboard = PhosphorIconsRegular.ranking;
  static const IconData streak = PhosphorIconsRegular.fire;
  static const IconData streakFilled = PhosphorIconsFill.fire;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData starFilled = PhosphorIconsFill.star;
  static const IconData idea = PhosphorIconsRegular.lightbulb;

  // ── Rangs (bronze → maître) ──────────────────────────────────
  static const IconData shield = PhosphorIconsRegular.shield;
  static const IconData shieldFilled = PhosphorIconsFill.shield;
  static const IconData flame = PhosphorIconsRegular.flame;
  static const IconData gridBoard = PhosphorIconsRegular.gridFour;
  static const IconData joystick = PhosphorIconsRegular.joystick;

  // ── Données & temps ──────────────────────────────────────────
  static const IconData chartBar = PhosphorIconsRegular.chartBar;
  static const IconData chartLine = PhosphorIconsRegular.chartLine;
  static const IconData chartDonut = PhosphorIconsRegular.chartDonut;
  static const IconData percent = PhosphorIconsRegular.percent;
  static const IconData history = PhosphorIconsRegular.clockCounterClockwise;
  static const IconData clock = PhosphorIconsRegular.clock;
  static const IconData calendar = PhosphorIconsRegular.calendarBlank;
  static const IconData calendarOff = PhosphorIconsRegular.calendarX;
  static const IconData rules = PhosphorIconsRegular.listChecks;
  static const IconData document = PhosphorIconsRegular.fileText;

  // ── Média & appareil ─────────────────────────────────────────
  static const IconData camera = PhosphorIconsRegular.camera;
  static const IconData gallery = PhosphorIconsRegular.images;
  static const IconData imageBroken = PhosphorIconsRegular.imageBroken;
  static const IconData mic = PhosphorIconsRegular.microphone;
  static const IconData volume = PhosphorIconsRegular.speakerHigh;
  static const IconData screen = PhosphorIconsRegular.monitor;
  static const IconData tv = PhosphorIconsRegular.television;

  // ── Réseau ───────────────────────────────────────────────────
  static const IconData wifi = PhosphorIconsRegular.wifiHigh;
  static const IconData wifiOff = PhosphorIconsRegular.wifiSlash;
  static const IconData cloudOff = PhosphorIconsRegular.cloudSlash;

  // ── Apparence ────────────────────────────────────────────────
  static const IconData palette = PhosphorIconsRegular.palette;
  static const IconData brightness = PhosphorIconsRegular.sunDim;
  static const IconData grid = PhosphorIconsRegular.squaresFour;
  static const IconData layers = PhosphorIconsRegular.stack;
}
