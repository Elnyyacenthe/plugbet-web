# 🎲 CORA DICE - Guide d'Activation Rapide

## ✅ ÉTAPE 1 : Migration SQL Supabase (3 minutes)

### 1.1 Connexion à Supabase
1. Ouvrez votre navigateur
2. Allez sur https://app.supabase.com
3. Connectez-vous à votre compte
4. Sélectionnez votre projet (le même que pour Ludo)

### 1.2 Exécution de la migration
1. Dans le menu de gauche, cliquez sur **SQL Editor**
2. Cliquez sur **New Query** (ou **Nouvelle requête**)
3. Ouvrez le fichier `supabase_migrations/05_cora_dice.sql` sur votre ordinateur
4. Copiez TOUT le contenu du fichier (481 lignes)
5. Collez-le dans l'éditeur SQL de Supabase
6. Cliquez sur le bouton **Run** (ou **Exécuter**) en bas à droite
7. Attendez 2-3 secondes

### 1.3 Vérification
1. Dans le menu de gauche, cliquez sur **Table Editor**
2. Vérifiez que vous voyez ces 4 nouvelles tables :
   - ✅ `cora_rooms`
   - ✅ `cora_games`
   - ✅ `cora_room_players`
   - ✅ `cora_messages`

Si vous ne voyez pas ces tables, relancez la migration.

---

## ✅ ÉTAPE 2 : Lancer l'Application (1 minute)

### 2.1 Ouvrir le terminal
Dans VSCode ou votre terminal :

```bash
cd C:\Users\ENY\Desktop\gost_app
```

### 2.2 Lancer l'app
```bash
flutter run
```

Ou si vous utilisez un émulateur spécifique :
```bash
flutter run -d chrome          # Pour le navigateur
flutter run -d windows         # Pour Windows desktop
flutter run -d <device-id>     # Pour un appareil spécifique
```

**Astuce** : Tapez `flutter devices` pour voir la liste des appareils disponibles.

---

## ✅ ÉTAPE 3 : Navigation et Test (5 minutes)

### 3.1 Tester la navigation
1. L'app démarre
2. En bas de l'écran, vous voyez 5 onglets :
   - ⚽ Matchs
   - ⭐ Favoris
   - 🎮 **Jeux** ← CLIQUEZ ICI
   - 💬 Chat
   - ⚙️ Réglages

3. Appuyez sur l'onglet **Jeux** (icône manette 🎮)

### 3.2 Vérifier l'écran Jeux
Vous devriez voir 2 grandes cartes :
- **Ludo** - Jeu de plateau classique • 2-4 joueurs
- **Cora Dice** - Jeu de dés camerounais • 2-6 joueurs • Virtual Coins

✅ Si vous voyez ces 2 cartes, la navigation fonctionne !

### 3.3 Entrer dans Cora Dice
1. Appuyez sur la carte **Cora Dice**
2. Vous arrivez sur l'écran principal de Cora Dice
3. Vous devriez voir :
   - Un header "CORA DICE 🎲"
   - Une liste vide (normal, aucune partie créée)
   - Deux boutons en bas :
     - **CRÉER** (vert)
     - **REJOINDRE** (bleu)

✅ Si vous voyez cet écran, Cora Dice est bien intégré !

---

## 🎮 ÉTAPE 4 : Test Complet avec 1 Appareil (Solo)

### 4.1 Créer une partie
1. Appuyez sur **CRÉER**
2. Écran de création :
   - Choisissez **2 joueurs** (cliquez sur le chiffre 2)
   - Mise : 200 coins (par défaut)
   - Laissez **Mode Public** (switch désactivé)
3. Appuyez sur **Créer la partie**

### 4.2 Lobby
Vous arrivez dans la salle d'attente :
- Vous voyez votre nom dans la grille (1/2 joueurs)
- Un slot vide pour le 2ème joueur
- Un code à 6 caractères en haut (ex: **A3F8D2**)
- Un bouton **PRÊT !** en bas

✅ Si vous voyez cet écran, la création fonctionne !

### 4.3 Tester le chat (facultatif)
1. En bas de l'écran, il y a un champ de texte
2. Écrivez "Test"
3. Appuyez sur l'icône avion ✈️
4. Votre message apparaît

---

## 🎮 ÉTAPE 5 : Test Multijoueur avec 2 Appareils

### Configuration requise
Vous avez besoin de **2 appareils** ou **2 émulateurs** :
- Option A : 1 téléphone physique + 1 émulateur
- Option B : 2 émulateurs (Android + iOS, ou 2 Android)
- Option C : 1 émulateur + 1 navigateur web (si Flutter Web activé)

### 5.1 Sur l'appareil 1
1. Lancez l'app
2. Allez dans **Jeux** → **Cora Dice**
3. Créez une partie **Publique** avec **2 joueurs**
4. Notez le code (ex: **B7K3M9**)
5. Restez dans le lobby

### 5.2 Sur l'appareil 2
1. Lancez l'app (même projet)
2. Allez dans **Jeux** → **Cora Dice**
3. Vous devriez voir la partie de l'appareil 1 dans la liste !
4. Appuyez sur **Join** (ou **Rejoindre**)
5. Vous entrez dans le lobby

### 5.3 Dans les 2 appareils
1. **Appareil 1** : Vous voyez maintenant 2 joueurs (vous + l'autre)
2. **Appareil 2** : Vous voyez 2 joueurs (vous + l'autre)
3. **Les deux** : Appuyez sur **PRÊT !**
4. **Magie** : La partie démarre automatiquement ! 🎉

### 5.4 Jouer une partie complète
1. **Tour 1** : L'appareil 1 voit "Votre tour"
2. Appuyez sur **LANCER LES DÉS**
3. Animation des dés qui tournent
4. Résultat affiché (ex: 3 + 4 = 7)
5. **Tour 2** : L'appareil 2 joue à son tour
6. **Fin** : Dialogue avec le résultat et les gains

---

## 🎯 ÉTAPE 6 : Tester les Règles Spéciales

### Test A : CORA (1+1) - Double Pot
**Objectif** : Obtenir 1+1 aux dés

1. Créez une partie à 2 joueurs
2. Lancez les dés plusieurs fois jusqu'à obtenir **1 + 1**
3. **Résultat attendu** :
   - ✅ Animation verte avec explosion
   - ✅ Message "CORA ! Double pot !"
   - ✅ Vous gagnez **800 coins** (400 × 2)
   - ✅ Vibration forte
   - ✅ La partie se termine immédiatement

### Test B : Le 7 (Perdre automatiquement)
**Objectif** : Obtenir un total de 7

1. Créez une partie à 2 joueurs
2. Lancez jusqu'à obtenir un **7** (ex: 3+4, 2+5, 1+6)
3. **Résultat attendu** :
   - ✅ Animation rouge avec tremblement
   - ✅ Message "7 ! Vous avez perdu"
   - ✅ L'autre joueur gagne automatiquement
   - ✅ Vibration moyenne

### Test C : Plus haut total gagne
**Objectif** : Score normal

1. **Joueur 1** : Obtient 5 + 3 = **8 points**
2. **Joueur 2** : Obtient 2 + 2 = **4 points**
3. **Résultat attendu** :
   - ✅ Joueur 1 gagne avec 8 points
   - ✅ Joueur 1 reçoit **400 coins** (200 × 2)

### Test D : Égalité
**Objectif** : Même score

1. **Joueur 1** : Obtient 4 + 4 = **8 points**
2. **Joueur 2** : Obtient 5 + 3 = **8 points**
3. **Résultat attendu** :
   - ✅ Message "Égalité !"
   - ✅ Partie annulée
   - ✅ Remboursement total (200 coins chacun)

### Test E : Plusieurs Cora
**Objectif** : 2 joueurs font Cora

1. Créez une partie à 3 joueurs
2. **Joueur 1** : 1 + 1 (Cora)
3. **Joueur 2** : 1 + 1 (Cora)
4. **Joueur 3** : n'importe quoi
5. **Résultat attendu** :
   - ✅ Message "Plusieurs Cora !"
   - ✅ Partie annulée
   - ✅ Remboursement total pour tous

---

## 🐛 DÉPANNAGE

### Problème 1 : "Table 'cora_rooms' doesn't exist"
**Cause** : La migration SQL n'a pas été exécutée
**Solution** : Retournez à l'ÉTAPE 1 et exécutez la migration

### Problème 2 : L'onglet "Jeux" n'apparaît pas
**Cause** : Le code n'a pas été recompilé
**Solution** :
```bash
flutter clean
flutter pub get
flutter run
```

### Problème 3 : La partie ne démarre pas
**Cause** : Tous les joueurs ne sont pas prêts
**Solution** : Vérifiez que TOUS les joueurs ont appuyé sur "PRÊT !"

### Problème 4 : Le realtime ne fonctionne pas
**Cause** : La publication realtime n'est pas activée
**Solution** : Dans Supabase SQL Editor, exécutez :
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE cora_rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_games;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_room_players;
ALTER PUBLICATION supabase_realtime ADD TABLE cora_messages;
```

### Problème 5 : Erreur "Function doesn't exist"
**Cause** : Les fonctions SQL n'ont pas été créées
**Solution** : Vérifiez que TOUTE la migration a été exécutée (481 lignes)

### Problème 6 : Les dés ne s'animent pas
**Cause** : Performance de l'émulateur
**Solution** : Utilisez un appareil physique ou activez l'accélération graphique

---

## 📊 CHECKLIST FINALE

Cochez chaque élément une fois testé :

**Base**
- [ ] Migration SQL exécutée
- [ ] 4 tables créées dans Supabase
- [ ] App lancée sans erreur
- [ ] Onglet "Jeux" visible
- [ ] Écran Cora Dice accessible

**Fonctionnalités**
- [ ] Création de partie
- [ ] Rejoindre une partie publique
- [ ] Rejoindre par code
- [ ] Chat dans le lobby
- [ ] Ready check fonctionne
- [ ] Partie démarre automatiquement
- [ ] Lancer de dés avec animation
- [ ] Tour par tour fonctionne
- [ ] Résultat final affiché

**Règles**
- [ ] Cora (1+1) gagne double pot
- [ ] 7 perd automatiquement
- [ ] Plus haut total gagne
- [ ] Égalité remboursée
- [ ] Plusieurs Cora annulent

---

## 🎉 FÉLICITATIONS !

Si vous avez coché tous les éléments, **Cora Dice est 100% fonctionnel** !

Vous pouvez maintenant :
- ✅ Jouer avec vos amis
- ✅ Créer des parties publiques ou privées
- ✅ Tester les différentes règles
- ✅ Personnaliser le jeu (sons, animations, etc.)

---

## 📱 PARTAGE AVEC VOS AMIS

Pour jouer avec vos amis :

1. **Vous** : Créez une partie **Privée** avec le nombre de joueurs souhaité
2. **Notez le code** (ex: C8F2K1)
3. **Partagez le code** à vos amis (WhatsApp, SMS, etc.)
4. **Vos amis** : Lancent l'app → Jeux → Cora Dice → Rejoindre → Entrent le code
5. **Tous** : Appuyez sur PRÊT !
6. **Jouez !** 🎲

---

## 🚀 PROCHAINES ÉTAPES (Optionnel)

Maintenant que Cora Dice fonctionne, vous pouvez ajouter :

### Niveau 1 : Polish (facile)
- [ ] Sons (lancer de dés, victoire, défaite)
- [ ] Confettis sur victoire
- [ ] Meilleure animation des dés (3D avec Rive)

### Niveau 2 : Fonctionnalités (moyen)
- [ ] Historique des parties
- [ ] Statistiques joueur (% victoires, nombre de Cora)
- [ ] Classement général
- [ ] Système de badges

### Niveau 3 : Avancé (difficile)
- [ ] Mode tournoi
- [ ] Notifications push pour invitations
- [ ] Replays de parties
- [ ] Variantes de règles (Cora x3, Cora x4)

---

**Bon jeu ! 🎲🎉**
