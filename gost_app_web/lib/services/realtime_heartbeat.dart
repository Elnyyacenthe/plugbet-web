// ============================================================
// RealtimeHeartbeat — Surveillance active du socket Realtime
// ============================================================
// Probleme : aujourd'hui le banner "hors ligne" n'apparait QUE
// lorsqu'une RPC echoue (NetworkRetry). Un joueur qui attend le coup
// de l'adversaire avec un socket Realtime mort ne voit rien : pas de
// RPC en cours -> pas de detection -> il croit que l'adversaire
// reflechit alors que la connexion est tombee.
//
// Solution : un heartbeat leger qui echantillonne l'etat du socket
// Realtime toutes les ~8s, UNIQUEMENT quand des canaux sont actifs
// (= on est dans une partie / salle). Si le socket est tombe -> on
// route vers ConnectivityService (banner + machinerie existante).
//
// Le client Realtime de Supabase se reconnecte deja tout seul
// (reconnectTimer interne) et rejoint ses canaux a la reconnexion.
// Ce heartbeat ne reimplemente PAS la reconnexion : il accelere la
// PRISE DE CONSCIENCE de la coupure.
//
// Regles : jamais de throw, zero impact gameplay, debounce anti-flap.
// ============================================================

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'connectivity_service.dart';

class RealtimeHeartbeat {
  RealtimeHeartbeat._();
  static final RealtimeHeartbeat instance = RealtimeHeartbeat._();

  static const _log = Logger('RT_HEARTBEAT');
  static const _interval = Duration(seconds: 8);
  // Nb de checks consecutifs "socket down + canaux actifs" avant de
  // declarer offline (anti-flap pendant un join normal).
  static const _missThreshold = 2;

  Timer? _timer;
  int _consecutiveMisses = 0;
  bool _flaggedOffline = false; // true si CE heartbeat a signale offline

  /// Demarre le heartbeat (idempotent). A appeler une fois apres
  /// l'init Supabase, au demarrage de l'app.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => _tick());
    _log.info('started (every ${_interval.inSeconds}s)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _consecutiveMisses = 0;
    _flaggedOffline = false;
  }

  void _tick() {
    try {
      final rt = Supabase.instance.client.realtime;

      // Pas de canaux actifs -> on n'est pas dans une partie. Le socket
      // peut etre legitimement ferme : ne rien signaler.
      if (rt.channels.isEmpty) {
        _consecutiveMisses = 0;
        if (_flaggedOffline) {
          // On etait offline a cause du RT mais on a quitte la partie :
          // on lache notre flag sans toucher ConnectivityService
          // (l'etat sera reevalue au prochain usage reseau).
          _flaggedOffline = false;
        }
        return;
      }

      if (rt.isConnected) {
        _consecutiveMisses = 0;
        if (_flaggedOffline) {
          _flaggedOffline = false;
          ConnectivityService.instance.notifyOnline(source: 'rt-heartbeat');
          _log.info('socket back up -> online');
        }
        return;
      }

      // Socket pas connecte ALORS QUE des canaux sont actifs.
      // (Le RealtimeClient declenche sa propre reconnexion via son
      // reconnectTimer interne ; on se contente de la detecter.)
      _consecutiveMisses++;

      if (_consecutiveMisses >= _missThreshold && !_flaggedOffline) {
        _flaggedOffline = true;
        ConnectivityService.instance.notifyOffline(source: 'rt-heartbeat');
        _log.warn('socket down with ${rt.channels.length} active channel(s) -> offline');
      }
    } catch (e) {
      // Ne jamais laisser le heartbeat casser quoi que ce soit.
      _log.info('tick error (ignored): $e');
    }
  }

}
