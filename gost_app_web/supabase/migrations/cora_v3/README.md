# Cora Dice V3 — Migration production-ready

## Ordre d'exécution OBLIGATOIRE

À exécuter dans Supabase SQL Editor, **dans cet ordre exact** :

```
01_wallet_ledger.sql           # Ledger immutable + RPCs internes
02_wallet_ledger_backfill.sql  # Backfill depuis user_profiles.coins (one-shot)
03_cora_consolidation.sql      # Drop anciennes RPCs + contraintes + config
04_cora_rls_lockdown.sql       # RLS lockdown + révocation grants legacy
05_cora_business_logic.sql     # Submit_roll + forfeit + RNG sécurisé
06_cora_lifecycle.sql          # Create/join/ready/leave + cleanup crons
07_cora_session_events.sql     # Events log + reprise + replay + history
08_cora_monitoring.sql         # Métriques + scan fraud + audit
```

---

## Pré-requis

- Extension `pgcrypto` (créée par 01)
- Extension `pg_cron` (optionnelle mais recommandée — sinon appeler les cleanup manuellement via app cron)
- Tables existantes : `user_profiles`, `treasury_balance`, `treasury_movements`, `game_treasury`, `admin_treasury`, `admin_alerts`, `cora_rooms`, `cora_games`, `cora_room_players`, `cora_messages`
- Fonction existante optionnelle : `check_rate_limit(text, text, int, interval)` — sinon les RPCs ignorent silencieusement

---

## Vérifications post-migration

### 1. Ledger initialisé pour tous les users
```sql
select count(distinct user_id) as users_with_ledger from wallet_ledger;
select count(*) from user_profiles where coins > 0;
-- Les deux nombres doivent matcher.
```

### 2. Aucune fonction sensible publique
```sql
select n.nspname||'.'||p.proname as fn,
       array_agg(r.rolname) as granted_to
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
left join pg_proc_acl a on a.proc_oid = p.oid
where n.nspname = 'public'
  and p.proname in ('treasury_refund_all','_ledger_post','_cora_start_game','_cora_secure_dice')
group by 1;
-- Aucune ne doit avoir 'authenticated' dans granted_to.
```

### 3. RLS lockdown
```sql
select tablename,
       (select count(*) from pg_policies pp where pp.tablename = pt.tablename and pp.cmd = 'INSERT') as ins,
       (select count(*) from pg_policies pp where pp.tablename = pt.tablename and pp.cmd = 'UPDATE') as upd,
       (select count(*) from pg_policies pp where pp.tablename = pt.tablename and pp.cmd = 'DELETE') as del
from pg_tables pt
where schemaname = 'public'
  and tablename in ('cora_rooms','cora_games','cora_room_players','wallet_ledger');
-- ins/upd/del doivent être 0 partout (sauf cora_messages qui a INSERT pour le chat).
```

### 4. Crons actifs
```sql
select jobname, schedule, active from cron.job where jobname like 'cora-%';
```

### 5. Test de bout en bout
```sql
-- Comme user A :
select cora_create_room(2, 200, false);
-- → {"room_id":"...", "code":"ABCDEF"}

-- Comme user B (autre session) :
select cora_join_room('ABCDEF');
-- → {"room_id":"...", "joined":true}

-- Les deux marquent ready :
select cora_toggle_ready('<room_id>', true);
-- Le 2e ready déclenche _cora_start_game

-- Vérifier la game créée :
select id, status, game_state from cora_games order by created_at desc limit 1;

-- User dont c'est le tour :
select cora_submit_roll('<game_id>');
-- → {"dice1":4, "dice2":3, "score":7, "is_finished":false, "is_cora":false}
-- (score=-1 affiché côté client si total=7, ici on retourne le total brut + flag)

-- Continuer jusqu'à fin de partie...

-- Vérifier le ledger final :
select * from wallet_ledger
  where game_id = '<game_id>'
  order by id;
-- Doit avoir : 2 'bet' (debits) + soit 1 'payout' (winner) + 1 'house_cut' implicite,
-- soit 2 'refund' (égalité/cancel).
```

---

## Côté client Flutter

Mettre à jour `cora_service.dart` :

```dart
// Nouveau wrapper avec idempotence (anti double-tap)
final Map<String, Future<dynamic>> _inFlight = {};
Future<T> _dedup<T>(String key, Future<T> Function() fn) async {
  if (_inFlight.containsKey(key)) return await _inFlight[key]! as T;
  final fut = fn();
  _inFlight[key] = fut;
  try { return await fut; } finally { _inFlight.remove(key); }
}

// Toutes les RPCs renommées avec préfixe cora_
Future<Map<String, dynamic>> createRoom({...}) =>
  _dedup('create:$_userId', () async => Map.from(await _client.rpc('cora_create_room', params: {...})));

Future<Map<String, dynamic>> joinRoom(String code) =>
  _dedup('join:$code', () async => Map.from(await _client.rpc('cora_join_room', params: {'p_code': code.toUpperCase()})));

Future<Map<String, dynamic>> toggleReady(String roomId, bool ready) =>
  _dedup('ready:$roomId:$ready', () async => Map.from(await _client.rpc('cora_toggle_ready', params: {'p_room_id': roomId, 'p_ready': ready})));

Future<Map<String, dynamic>?> submitRoll(String gameId) =>
  _dedup('roll:$gameId', () async => Map.from(await _client.rpc('cora_submit_roll', params: {'p_game_id': gameId})));

Future<void> forfeit(String gameId) =>
  _dedup('forfeit:$gameId', () async => await _client.rpc('cora_forfeit', params: {'p_game_id': gameId}));

Future<void> leaveRoom(String roomId) =>
  _dedup('leave:$roomId', () async => await _client.rpc('cora_leave_room', params: {'p_room_id': roomId}));

Future<Map<String, dynamic>?> getActiveSession() async {
  final r = await _client.rpc('cora_get_active');
  return r is Map ? Map<String, dynamic>.from(r) : null;
}

Future<void> sendMessage(String roomId, String message) =>
  _dedup('msg:$roomId:${DateTime.now().millisecondsSinceEpoch}', () async =>
    await _client.rpc('cora_send_message', params: {'p_room_id': roomId, 'p_message': message}));
```

Mettre à jour `game_screen.dart` :
- `_confirmExit` → appeler `cora_forfeit()` avant `Navigator.pop`
- `dispose` → appeler `cora_forfeit()` si `game.status == 'playing'`
- Remplacer `result.contains('annulé')` par `_game!.gameState.isCancelled` (flag explicite)
- Ajouter `==` override sur `DiceRoll` pour éviter double animation
- Au boot de `MainShell.didChangeAppLifecycleState(AppLifecycleState.resumed)` → appeler `getActiveSession` et naviguer si game/room active

---

## Rollback

Aucune migration n'est destructive (drop des fonctions + recreate). Si problème :

```sql
-- Désactiver les crons
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname like 'cora-%';
end $$;

-- Restaurer un backup Supabase (Pro plan : Point-in-Time Recovery)
```

Le ledger lui-même est immutable et conserve l'historique exact de toutes les transactions.

---

## Risques résiduels

1. **RNG biais résiduel** : `gen_random_bytes % 6` avec rejection sampling à 252 (4 valeurs/256 rejetées). Biais effectif < 0.001%.
2. **Collusion** : 2-3 amis qui jouent ensemble pour se transférer de l'argent. Détection partielle via pattern 3 du scan_fraud.
3. **DoS niveau Postgres** : pas de limite SQL au nombre de connexions concurrentes. À gérer via Supabase pooler + Cloudflare devant.
4. **Latence réseau client** : timeouts 25s configurables. Sur 4G CMR moyenne ça suffit.
5. **Crash Postgres pendant transaction** : ROLLBACK automatique (atomicité ACID).

---

## Migration des autres jeux (Mines, Aviator, Ludo, Blackjack...)

Le `wallet_ledger` (01) est universel. Pour chaque autre jeu :

1. Adapter le pattern `cora_place_bet`/`cora_pay_winner`/`cora_refund_participants` avec préfixe du jeu.
2. Adapter le `submit_*` avec FOR UPDATE + advisory lock + RNG sécurisé si dés.
3. Lockdown RLS UPDATE/DELETE/INSERT sur les tables du jeu.
4. Ajouter cleanup crons stuck/stale.
5. Ajouter `<jeu>_get_active` dans la même logique.
6. Ajouter monitoring/scan_fraud par jeu.

L'architecture est réutilisable telle quelle.
