# Plugbet — Analyse Architecture Profits

**Date** : 2026-05-05
**Objectif** : auditer le flux d'argent de chaque jeu et identifier les failles qui empechent l'app de generer des profits comme un casino.

---

## 1. Modele economique attendu (cible)

Pour chaque partie, le flux d'argent doit suivre ce schema :

```
Joueurs → MISES → POT TOTAL
                      ↓
             ┌────────┴────────┐
             ↓                 ↓
      WINNER reçoit     SUPER-ADMIN reçoit
       (1 - X%) × pot       X% × pot
```

Ou `X%` = `house_edge` configurable par jeu (typiquement 5-15%).

**Garantie business** : meme si tous les joueurs gagnent leur partie, l'app **encaisse toujours** `X%` du pot.

---

## 2. Etat actuel — Audit par jeu

### 2.1 Jeux qui passent par la caisse admin (✅ OK)

| Jeu | RPCs treasury | House edge | Notes |
|---|---|---|---|
| **Aviator** | `game_treasury_collect_loss`, `game_treasury_pay_win` | Implicit (RTP 90% = 10% edge) | Correct. Distribution Pareto avec edge integre. |
| **Solitaire** | `game_treasury_collect_loss`, `game_treasury_pay_win` | Inconnu | A verifier le pourcentage applique. |

### 2.2 Jeux qui NE passent PAS par la caisse (❌ FAILLE)

| Jeu | RPC settlement actuelle | Probleme |
|---|---|---|
| Apple Fortune | `cashout_apple_fortune_session` | Paie le winner direct, **0% pour la maison** |
| Blackjack | `bj_auto_continue` | Pot redistribue entre joueurs sans deduction |
| Coinflip | `cf_auto_continue` | Winner prend 100% du pot |
| Cora Dice | `cora_auto_continue` | Winner prend 100% du pot |
| Mines | `cashout_mines_session` | Multiplicateur sans deduction |
| Roulette | `rlt_auto_continue` | Paiements de paris standards sans edge |
| Ludo v1 | `finish_ludo_game` | Winner prend tout |
| Ludo v2 | `ludo_v2_play_move` (settle final) | Winner prend tout |
| Fantasy | `fantasy_finish_league` | Pot ligue redistribue 100% |

**Verdict** : 9 jeux sur 11 ne genere PAS de profit pour ton business actuellement.

---

## 3. Failles architecturales identifiees

### Faille 1 : Pas de table `house_edge_config`
Il n'existe aucune table centralisee pour configurer le pourcentage de commission par jeu. Donc :
- Impossible d'ajuster le edge sans deployer du code
- Pas de transparence pour audit/legal
- Pas de historique des changements

### Faille 2 : Pas de log `treasury_movements`
Chaque RPC de jeu paye/prend de l'argent sans tracer :
- Qui a perdu combien
- Vers quelle caisse
- Pour quelle raison
→ Impossible de prouver les revenus, calculer la marge reelle, detecter les bugs

### Faille 3 : Logique payout dispersee
Chaque jeu a sa propre fonction de paiement, avec des regles differentes. Risque :
- Bug dans une RPC = fuite d'argent
- Maintenance lourde (10 fonctions a maintenir)
- Pas de coherence entre jeux

### Faille 4 : Pas de gestion des matches nuls
Quand 2 joueurs sont a egalite (Coinflip, Ludo, Cora Dice), que faire du pot ?
- Le retourner integralement ? (perte pour la maison)
- Garder la commission quand meme ?
- Rejouer ?

### Faille 5 : Pas de plafond de gain
Aucun jeu ne limite les gains max par session, ce qui expose aux bugs/exploits qui pourraient drainer la caisse.

---

## 4. Architecture proposee — Treasury Unifie

### 4.1 Table de config

```sql
create table public.house_edge_config (
  game_type text primary key,
  edge_pct numeric(5,4) not null,       -- ex: 0.0700 = 7%
  min_pot int not null default 0,
  max_payout int,                         -- plafond optionnel
  on_draw text default 'refund_minus_edge', -- 'refund' | 'refund_minus_edge' | 'house_keeps'
  enabled boolean not null default true,
  updated_at timestamptz default now()
);
```

### 4.2 Table de log

```sql
create table public.treasury_movements (
  id uuid primary key default gen_random_uuid(),
  game_type text not null,
  game_id text,                           -- id de la partie
  user_id uuid references auth.users(id),
  movement_type text not null,            -- 'house_cut' | 'payout' | 'refund' | 'jackpot'
  amount int not null,
  pot_total int,
  edge_pct numeric(5,4),
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);
create index idx_treasury_movements_game on public.treasury_movements(game_type, created_at desc);
create index idx_treasury_movements_user on public.treasury_movements(user_id);
```

### 4.3 RPC unifiee `apply_game_payout`

Toute fonction de jeu qui doit payer un winner DOIT passer par cette RPC :

```sql
-- Distribue le pot : (1 - edge) au winner + edge a la caisse super-admin.
-- Atomique : si n'importe quoi echoue → rollback complet.
create or replace function public.apply_game_payout(
  p_game_type text,
  p_game_id text,
  p_winner_id uuid,
  p_pot_total int
) returns int   -- retourne le net paye au winner
language plpgsql security definer
as $$ ... $$
```

Voir le fichier SQL pour l'implementation complete.

### 4.4 Plan de migration des jeux existants

Chaque RPC `*_auto_continue`, `finish_*`, `cashout_*` doit etre modifiee pour :
1. Calculer le pot total
2. Appeler `apply_game_payout()` au lieu de creditier directement le winner
3. Ne plus debiter/crediter manuellement le winner

---

## 5. House edge recommandes (par type de jeu)

| Type de jeu | Jeux | Edge recommande |
|---|---|---|
| **Solo (vs maison)** | Apple Fortune, Mines, Solitaire | **8-10%** |
| **Crash / Multiplicateur** | Aviator | **10%** (deja en place) |
| **Duel (1v1)** | Coinflip, Pile ou Face | **5-7%** |
| **Multi-joueurs (2-4)** | Ludo, Cora Dice, Checkers, Blackjack | **7-10%** |
| **Multi grande table** | Roulette | **5-8%** |
| **Tournois longue duree** | Fantasy League | **10-15%** sur entry fees |

**Total marge attendue** : entre 7% et 12% du volume mise selon le mix de jeux.

---

## 6. Roadmap de mise en place

### Phase 1 — Infrastructure (cette session)
- [x] Audit complet (ce document)
- [ ] Creer SQL `treasury_unified.sql` avec :
  - Tables `house_edge_config` + `treasury_movements`
  - RPC `apply_game_payout`
  - RPC `treasury_get_balance` (lecture du solde caisse)
- [ ] Seed les pourcentages dans `house_edge_config`

### Phase 2 — Migration jeu par jeu (priorite)
1. **Roulette** (plus de volume) — modifier `rlt_auto_continue`
2. **Coinflip** — modifier `cf_auto_continue`
3. **Cora Dice** — modifier `cora_auto_continue`
4. **Blackjack** — modifier `bj_auto_continue`
5. **Mines** — modifier `cashout_mines_session`
6. **Apple Fortune** — modifier `cashout_apple_fortune_session`
7. **Ludo v1 + v2** — modifier les `finish_*`
8. **Fantasy** — modifier `fantasy_finish_league`

Pour chaque jeu, je peux te livrer le patch SQL si tu me partages la version actuelle de la fonction.

### Phase 3 — Dashboard admin
- Lecture en temps reel de `treasury_movements`
- Graphes : revenus par jeu, par jour, par joueur
- Alertes : pertes anormales (un joueur gagne 10× son volume mise)

### Phase 4 — Anti-fraude
- Limite max payout par partie
- Detection des comptes complices (2 users qui s'echangent toujours)
- Cooldown entre parties pour les gagnants reguliers

---

## 7. Risques business si on ne fait rien

| Risque | Impact |
|---|---|
| **App genere zero profit** sur 9/11 jeux | Critique — modele economique casse |
| **Difficulte a monetiser** avec des partenaires | Eleve — pas de chiffre d'affaires demontrable |
| **Risque de deficit** si winner a un coup de chance | Eleve — la "caisse" personne paye |
| **Pas de barriere a la fraude** | Moyen — pas de log treasury |

---

## 8. Prochaines actions concretes

1. **Toi** : Tu valides les pourcentages de section 5 (ou tu me donnes les tiens)
2. **Moi** : Je livre `treasury_unified.sql` avec les tables + RPCs centrales
3. **Toi** : Tu m'envoies le code SQL de 1-2 RPCs settlement existantes (`rlt_auto_continue`, `cf_auto_continue`...) — je peux les recuperer depuis Supabase Dashboard → Database → Functions
4. **Moi** : Je te livre les patches SQL pour chaque jeu, integration tracable
5. **Toi** : Tu executes les SQL dans Supabase SQL Editor
6. **Moi** : Je sync le code Dart si necessaire (parfois les RPCs changent de signature)

---

**Resume tres court** : ton app n'est PAS un casino actuellement, c'est un casino-like ou les joueurs s'echangent l'argent entre eux. Pour devenir un vrai business profitable, on doit centraliser tous les payouts via une caisse admin avec house_edge applique systematiquement.
