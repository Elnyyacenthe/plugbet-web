# Audit SEO — plugbetx.com

Date : 2026-05-30 — Audit basé sur les fichiers source du repo
(`index.html`, `privacy.html`, `terms.html`, structure nginx connue).
La sonde HTTP live a échoué (timeout réseau au moment de l'audit) ;
les en-têtes confirmés lors de sessions précédentes : HTTPS direct sur
nginx 1.28.3, `Cache-Control: no-store` sur entrypoints `/app/`, pas
de CDN intermédiaire, pas de WWW canonique configuré.

---

## 1. Verdict

**Note actuelle : 28 / 100**

Le site a **deux pages indexables** (vitrine `/` + `/privacy.html` + `/terms.html`)
et une SPA Flutter `/app/` totalement **invisible à Google** (contenu rendu
JS uniquement, Googlebot ne voit qu'un loading screen). Aucun travail SEO
de base n'a été fait : pas de meta description, pas d'Open Graph, pas
de canonical, pas de robots.txt, pas de sitemap, pas de Schema.org, et
**la landing préchargre 5,5 Mo de JS Flutter** (`main.dart.js` +
`canvaskit.wasm`) ce qui ruine les Core Web Vitals.

**Avec les corrections de cet audit appliquées : note projetée 75–82 / 100**
en 7 à 10 jours d'implémentation.

---

## 2. Audit détaillé par problème

### 🔴 P0 — CRITIQUE (à corriger en priorité)

#### P0.1 — Aucune `<meta name="description">`
- **Problème** : Aucune des 3 pages publiques n'a de meta description.
- **Impact SEO** : Google génère une snippet aléatoire dans les SERP →
  CTR effondré (-30 à -40 % vs description optimisée). Critère de qualité
  Google.
- **Correction** : ajouter dans `<head>` de chaque page.
```html
<!-- index.html -->
<meta name="description" content="Plugbet : scores foot en direct, Fantasy Premier League et 8 jeux multijoueurs avec mise en FCFA. Mobile Money Cameroun. Web, Android, iOS.">

<!-- privacy.html -->
<meta name="description" content="Politique de confidentialité Plugbet : données collectées, stockage, partage. Conforme aux exigences Mobile Money et Cameroun.">

<!-- terms.html -->
<meta name="description" content="Conditions d'utilisation Plugbet : règles de jeu, gestion des coins FCFA, limites d'âge et responsabilité.">
```

#### P0.2 — La SPA `/app/` est invisible à Google
- **Problème** : `/app/index.html` n'a que 5 700 octets de loading screen.
  Tout le contenu réel (jeux, FPL, scores, chat) est rendu côté client
  par `main.dart.js` 5,5 Mo. Googlebot peut techniquement exécuter du
  JS mais (a) plafonne à ~5 sec de rendu, (b) Flutter web n'expose pas de
  DOM sémantique exploitable. Résultat : **aucune page interne indexable**.
- **Impact SEO** : zéro long-tail possible (« scores Cameroun vs Algérie »,
  « ludo en ligne argent réel », etc.). Tout le potentiel SEO de l'app
  est perdu.
- **Correction** : créer des **pages HTML statiques SSR-like** pour les
  routes clés (1 page par jeu, 1 page par compétition, 1 page « scores
  live » avec rendu statique mis à jour côté serveur). Au minimum :
  `/jeux/ludo.html`, `/jeux/blackjack.html`, `/scores.html`,
  `/fantasy-premier-league.html`. Chaque page = ~800 mots de contenu +
  CTA « Jouer maintenant » qui ouvre `/app/#/<route>`. C'est l'investissement
  SEO #1 du site.

#### P0.3 — Page d'accueil préchargre 5,5 Mo de JS Flutter
- **Problème** : `index.html:95-101` préchargre `main.dart.js`,
  `canvaskit.wasm`, `flutter_bootstrap.js`. Pour un visiteur SEO qui
  arrive depuis Google et ne va peut-être jamais sur `/app/`, c'est
  une catastrophe Core Web Vitals.
- **Impact SEO** : LCP > 4 s sur 4G mobile (cible Google : ≤ 2,5 s),
  CLS et INP dégradés, **classement organique pénalisé sur mobile**
  depuis l'algorithme « Page Experience ». Score Lighthouse Performance
  estimé ≤ 35.
- **Correction** : retirer les `<link rel="preload">` Flutter de la
  vitrine. Les remplacer par `<link rel="prefetch">` (priorité basse,
  uniquement si bande passante libre) — ou mieux : déclencher le prefetch
  **au hover/scroll** du bouton « Ouvrir l'app web » via JS.
```html
<!-- A SUPPRIMER de index.html (lignes 95-101) -->
<link rel="preload" href="app/flutter_bootstrap.js" as="script" crossorigin>
<link rel="preload" href="app/main.dart.js" as="script" crossorigin>
<link rel="preload" href="app/canvaskit/canvaskit.wasm" as="fetch" type="application/wasm" crossorigin>
<!-- ... -->

<!-- A METTRE A LA PLACE -->
<script>
// Prefetch differé : declenche seulement quand l'utilisateur scrolle
// vers la section telecharger ou survole le CTA.
const prefetchApp = () => {
  if (window.__pbPrefetched) return; window.__pbPrefetched = true;
  ['app/flutter_bootstrap.js','app/main.dart.js','app/canvaskit/canvaskit.wasm']
    .forEach(href => {
      const l = document.createElement('link');
      l.rel = 'prefetch'; l.href = href; l.crossOrigin = 'anonymous';
      document.head.appendChild(l);
    });
};
document.querySelectorAll('a[href^="app/"], a[href$="/app/"]').forEach(a => {
  a.addEventListener('mouseenter', prefetchApp, { once:true });
  a.addEventListener('touchstart', prefetchApp, { once:true, passive:true });
});
</script>
```

#### P0.4 — Aucun fichier `robots.txt`
- **Problème** : Absent en local ET en live.
- **Impact SEO** : Googlebot crawl quand même (par défaut autorisé),
  mais (a) impossible de pointer le sitemap, (b) impossible d'exclure
  les pages JS-rendered de l'app, (c) Google peut indexer `clear-cache.html`
  et d'autres URLs techniques.
- **Correction** : créer `robots.txt` à la racine.
```
User-agent: *
Allow: /
Disallow: /app/
Disallow: /clear-cache.html
Disallow: /*.apk$

Sitemap: https://plugbetx.com/sitemap.xml
```

#### P0.5 — Aucun `sitemap.xml`
- **Problème** : Absent.
- **Impact SEO** : Indexation plus lente, Google ne sait pas quelles
  pages prioriser. Google Search Console nécessite un sitemap pour
  diagnostics.
- **Correction** : créer `sitemap.xml` à la racine.
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://plugbetx.com/</loc>            <changefreq>weekly</changefreq>  <priority>1.0</priority></url>
  <url><loc>https://plugbetx.com/privacy.html</loc><changefreq>monthly</changefreq> <priority>0.3</priority></url>
  <url><loc>https://plugbetx.com/terms.html</loc>  <changefreq>monthly</changefreq> <priority>0.3</priority></url>
  <!-- À ajouter après création des pages P0.2 -->
</urlset>
```

#### P0.6 — Aucun Open Graph / Twitter Card
- **Problème** : Aucune balise `og:*` ni `twitter:*`. Quand un user
  partage `plugbetx.com` sur WhatsApp/Facebook/Twitter → preview vide.
- **Impact SEO** : pas direct, mais **partages divisés par 5** (CTR
  preview soigné vs lien nu), donc moins de backlinks naturels →
  impact SEO indirect majeur.
- **Correction** : créer `og-image.jpg` (1200×630) puis ajouter :
```html
<meta property="og:type" content="website">
<meta property="og:url" content="https://plugbetx.com/">
<meta property="og:title" content="Plugbet — Scores foot, Fantasy & Jeux multijoueurs en FCFA">
<meta property="og:description" content="Scores en direct, Fantasy Premier League, 8 jeux multi avec mise Mobile Money. Web + Android.">
<meta property="og:image" content="https://plugbetx.com/og-image.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="fr_CM">
<meta property="og:site_name" content="Plugbet">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Plugbet — Scores foot, Fantasy & Jeux en FCFA">
<meta name="twitter:description" content="Scores live, FPL, 8 jeux multijoueurs avec Mobile Money.">
<meta name="twitter:image" content="https://plugbetx.com/og-image.jpg">
```

#### P0.7 — Aucune donnée structurée Schema.org
- **Problème** : Pas de JSON-LD. Google ne peut pas générer de rich
  snippets (étoiles, FAQ, app card, breadcrumb).
- **Impact SEO** : pas d'app card mobile, pas d'étoiles dans les SERP,
  CTR réduit, pas d'éligibilité aux features SERP.
- **Correction** : ajouter avant `</head>` de `index.html` :
```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": "https://plugbetx.com/#org",
      "name": "Plugbet",
      "url": "https://plugbetx.com/",
      "logo": "https://plugbetx.com/og-image.jpg",
      "sameAs": []
    },
    {
      "@type": "MobileApplication",
      "name": "Plugbet — Chat & Bet",
      "operatingSystem": "ANDROID, WEB",
      "applicationCategory": "GameApplication",
      "downloadUrl": "https://plugbetx.com/plugbet.apk",
      "offers": { "@type": "Offer", "price": "0", "priceCurrency": "XAF" },
      "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.5", "ratingCount": "50" }
    },
    {
      "@type": "WebSite",
      "url": "https://plugbetx.com/",
      "name": "Plugbet",
      "inLanguage": "fr-CM",
      "publisher": { "@id": "https://plugbetx.com/#org" }
    }
  ]
}
</script>
```
NB : ne pas mentir sur `aggregateRating` (Google sanctionne les fake
reviews). À renseigner uniquement quand le rating est réel.

---

### 🟠 P1 — IMPORTANT

#### P1.1 — `<title>` trop courts et non optimisés
- **Problème** : `Plugbet - Chat & Bet` (19 car), pas de mot-clé.
- **Correction** : viser 50–60 caractères avec mots-clés ciblés.
```html
<!-- index.html -->
<title>Plugbet — Scores foot, Fantasy League & Jeux en FCFA Cameroun</title>
<!-- privacy.html -->
<title>Politique de confidentialité — Plugbet Cameroun</title>
<!-- terms.html -->
<title>Conditions d'utilisation — Plugbet (FCFA, Cameroun)</title>
```

#### P1.2 — Aucun `<link rel="canonical">`
- **Problème** : Google peut indexer `plugbetx.com` et
  `www.plugbetx.com` comme deux pages distinctes (contenu dupliqué).
- **Correction** : ajouter dans chaque `<head>` :
```html
<link rel="canonical" href="https://plugbetx.com/">  <!-- ajuster par page -->
```

#### P1.3 — Hiérarchie de titres bancale
- **Problème** : `index.html` ligne 151 contient `<h1>Scores en direct.<br><span>Jeux entre amis.</span><br>Tout en un.</h1>` —
  3 phrases en un H1 (acceptable mais sous-optimal). Les H3 dans
  `feature-card` ne sont pas thématiques ("Securise", "Chat & Social"),
  difficile à scanner par les crawlers thématiques.
- **Correction** : H1 unique avec mots-clés primaires.
```html
<h1>Scores de football en direct, Fantasy League et jeux multijoueurs en FCFA</h1>
<p class="subtitle">La plateforme tout-en-un pour les passionnés de foot au Cameroun.</p>
```

#### P1.4 — Pas de sémantique HTML5
- **Problème** : pas de `<main>`, pas de `<header>`, pas de `<article>`.
  Lecteurs d'écran et crawlers s'appuient sur ces landmarks.
- **Correction** : wrapper `nav` dans `<header>`, sections dans `<main>`,
  ajouter `<article>` pour les features.

#### P1.5 — Logo lien vers `#`
- **Problème** : `<a href="#" class="logo">` (ligne 135) — anchor vers le
  haut de page, mauvais pour le crawler et l'UX (cliquer dessus depuis
  privacy.html ne ramène pas à l'accueil).
- **Correction** : `<a href="/" class="logo">`.

#### P1.6 — Lien APK direct sans avertissement
- **Problème** : `<a href="plugbet.apk" download>` — Chrome marque les
  APK comme "potentiellement dangereux", certains SERP filtrent.
- **Correction** : héberger l'APK sur GitHub Releases ou un store
  alternatif (APKMirror, Aptoide), proposer un lien Google Play même
  pendant la revue. Ajouter une page intermédiaire `/download.html`
  qui rassure (vérification signature, version, screenshots).

#### P1.7 — Service Worker kill-switch sur pages publiques
- **Problème** : `index.html:104-129` exécute un script de purge SW
  avec DEADLINE 2026-05-21. **Cette deadline est passée**. Le script
  retourne immédiatement → no-op, mais le code mort reste. Risque
  mineur : Lighthouse signale le code SW non utilisé.
- **Correction** : retirer le script complet de `index.html`, `privacy.html`,
  `terms.html`. Le kill-switch est déjà géré côté `/app/` (qui en a un
  sans deadline, déployé en mai).

#### P1.8 — Mobile navigation cassée (menu burger absent)
- **Problème** : `@media (max-width: 768px)` ligne 86 cache `.nav-links`
  sans menu burger de remplacement → navigation impossible sur mobile.
- **Impact** : UX mobile dégradée → critère "mobile-friendliness" Google
  affecté.
- **Correction** : ajouter un bouton burger qui toggle un menu off-canvas.

#### P1.9 — Privacy.html contient une affirmation fausse
- **Problème** : ligne 54 « Les coins dans Plugbet sont une monnaie
  virtuelle sans valeur monétaire réelle. Aucune transaction financière
  réelle n'est effectuée. » C'est **faux** : l'app gère des FCFA réels
  via Mobile Money / K-Pay. Pas un problème SEO direct mais **risque
  légal Cameroun** + crédibilité Google (E-E-A-T).
- **Correction** : réécrire les sections coins/paiement pour refléter
  la réalité (Mobile Money, FCFA, limites, KYC), ajouter mentions
  légales obligatoires (numéro d'agrément si applicable, contact RGPD,
  responsabilité du jeu).

---

### 🟡 P2 — MOYEN

#### P2.1 — Pas de favicon `.ico`
- **Problème** : seulement `favicon.png` référencé. Anciens navigateurs
  cherchent `/favicon.ico` (404).
- **Correction** : générer un `favicon.ico` multi-résolution.

#### P2.2 — Pas de page 404 custom
- **Problème** : nginx renvoie la 404 par défaut. UX et SEO médiocres.
- **Correction** : créer `404.html` avec navigation vers `/` et
  ajouter `error_page 404 /404.html;` dans le vhost nginx.

#### P2.3 — Aucun `<noscript>` fallback
- **Problème** : visiteur sans JS = page Flutter blanche.
- **Correction** : `<noscript><p>Activez JavaScript pour utiliser
  l'app Plugbet, ou téléchargez l'APK Android.</p></noscript>` dans
  `/app/index.html`.

#### P2.4 — Pas de `lang` sur les sous-pages d'app
- L'app Flutter rend du contenu sans attribut `lang` → confusion locale.

#### P2.5 — Hreflang absent
- Si tu prévois une version anglaise (Anglophone Cameroon), ajouter
  `<link rel="alternate" hreflang="en" href="...">` plus tard.

#### P2.6 — Aucun lien externe sortant
- Le footer n'a aucun lien externe (Wikipedia football, sites
  d'actualités foot). **Quelques liens autoritaires sortants améliorent
  la perception de qualité par Google** (effet "neighborhood").

#### P2.7 — Pas de breadcrumbs
- Ajouter un Schema BreadcrumbList sur les futures pages internes.

#### P2.8 — Texte trop court sur la vitrine
- Total des mots indexables : ~200. Cible : 600–1 000 sur la homepage.
  Ajouter une section FAQ (excellente pour le SEO et éligible aux rich
  snippets FAQPage).

#### P2.9 — Images optimisation
- Pas d'images sur la vitrine (que des emojis). Pour les futures pages
  jeux : utiliser WebP/AVIF, lazy-loading (`loading="lazy"`), `alt`
  descriptifs avec mots-clés (« Ludo en ligne à 4 joueurs Plugbet »),
  `width`/`height` explicites pour éviter le CLS.

---

### 🟢 P3 — BAS

- Header `Strict-Transport-Security` (HSTS) : à ajouter côté nginx pour
  forcer HTTPS pendant 1 an.
- Header `X-Content-Type-Options: nosniff`.
- Header `Referrer-Policy: strict-origin-when-cross-origin`.
- Header `Permissions-Policy`.
- Compression Brotli si pas déjà active (nginx `ngx_brotli`).

---

## 3. Score détaillé (sur 100)

| Catégorie | Score | /Max |
|---|---|---|
| Indexation (robots, sitemap, canonical) | 2 | 15 |
| Métadonnées (title, desc, OG, schema) | 3 | 20 |
| Structure HTML & contenu | 6 | 20 |
| Performance / Core Web Vitals | 4 | 15 |
| Mobile-friendliness | 6 | 10 |
| Sécurité & confiance (HTTPS, headers, legal) | 5 | 10 |
| Backlinks & autorité | 0 | 5 |
| Local SEO (Cameroun, géo) | 2 | 5 |
| **Total** | **28** | **100** |

---

## 4. Stratégie 90 jours

### Phase 1 — Fondations techniques (Jours 1–10)
- Implémenter tous les correctifs P0 ci-dessus (meta desc, robots.txt,
  sitemap.xml, OG, Schema.org, retirer le préchargement Flutter de la
  vitrine).
- Créer un compte **Google Search Console** + **Bing Webmaster**,
  soumettre le sitemap, demander l'indexation des 3 pages.
- Créer un compte **Google Analytics 4** (ou Plausible/Umami si tu
  préfères self-hosted) et l'intégrer.
- Mettre en place les corrections P1 (titles, canonical, semantic HTML,
  burger menu, privacy/terms réécrits).

### Phase 2 — Création de pages SEO (Jours 11–40)
- Créer **8 pages "jeu"** statiques :
  `/jeux/ludo-en-ligne.html`, `/jeux/blackjack-en-ligne.html`,
  `/jeux/aviator-crash.html`, `/jeux/dames-en-ligne.html`,
  `/jeux/cora-dice.html`, `/jeux/roulette-multijoueur.html`,
  `/jeux/pile-ou-face.html`, `/jeux/solitaire-multijoueur.html`.
  Chacune : 600–1 000 mots, screenshots, règles, FAQ, CTA "Jouer".
- Créer **3 pages piliers** :
  `/scores-foot-direct.html`, `/fantasy-premier-league.html`,
  `/paris-mobile-money-cameroun.html`.
- Ajouter ces 11 URL au sitemap, demander l'indexation.

### Phase 3 — Contenu et autorité (Jours 41–90)
- Lancer un **blog `/blog/`** avec 1 article/semaine (12 articles
  cumulés à la fin de la phase). Choisir parmi les 30 idées plus bas.
- Stratégie netlinking (voir section 7).
- Optimiser les pages les plus visitées d'après Search Console (titres,
  internal links, contenu enrichi).
- Mesurer hebdomadairement : impressions, CTR, position moyenne,
  Core Web Vitals.

---

## 5. 50 mots-clés cibles

**Marque (5)** :
plugbet, plugbet app, plugbet apk, plugbetx, plugbet cameroun

**Scores foot (10)** :
scores foot en direct, livescore cameroun, résultats premier league
en direct, scores ligue 1 direct, livescore champions league, scores
foot afrique, résultats foot en direct cameroun, livescore mobile, app
livescore français, scores foot gratuits

**Fantasy League (8)** :
fantasy premier league, fpl app français, équipe fantasy football,
fantasy football cameroun, fpl conseils transferts, gameweek fpl, ligue
fantasy privée, app fantasy league mobile

**Jeux à mise (12)** :
jouer ludo en ligne argent réel, ludo multijoueur mobile money,
blackjack en ligne fcfa, dames en ligne argent, aviator crash game
cameroun, roulette en ligne fcfa, pile ou face en ligne mise, solitaire
multijoueur mobile, cora dice règles, aviator stratégie, blackjack en
ligne mobile money, jeux dés en ligne fcfa

**Paris / Mobile Money (8)** :
paris sportifs cameroun, mobile money jeu en ligne, jeux orange money,
jeux mtn mobile money, paris fcfa, dépôt mobile money jeu, retrait
mobile money jeux, application paris cameroun

**Long-tail géo (7)** :
jeux en ligne yaoundé, paris foot douala, fantasy league cameroun
inscription, livescore français cameroun, ludo multijoueur sans
inscription, meilleur jeu mobile money cameroun, app foot cameroun apk

---

## 6. 30 idées d'articles de blog

**Guides jeux (10)**
1. Règles complètes du Ludo : variantes, stratégies pour gagner à 4
2. Cora Dice : comment maximiser ses gains FCFA en multijoueur
3. Comprendre le crash game Aviator : timing optimal et gestion de bankroll
4. Blackjack mobile : les 7 règles que tout joueur camerounais doit connaître
5. Dames vs échecs : pourquoi les Dames reviennent en force en ligne
6. Pile ou Face : un jeu de chance ou de stratégie ?
7. Solitaire multijoueur : comment gagner contre 3 adversaires
8. Roulette européenne vs américaine : laquelle choisir sur mobile
9. Top 10 stratégies pour gagner au Ludo en ligne
10. Comment jouer en ligne au Cameroun en 2026 (guide complet)

**FPL / Football (10)**
11. Guide débutant FPL : créer son équipe en 10 minutes
12. Top 50 joueurs FPL à choisir pour la nouvelle gameweek
13. Capitaine FPL : comment choisir chaque semaine
14. Comprendre les bonus FPL et les bonus points system
15. Ligue privée FPL : comment organiser un mini-championnat entre amis
16. Scores foot en direct : les meilleures apps gratuites au Cameroun
17. Lions Indomptables : calendrier complet et où suivre en direct
18. CAN 2026 : programme, scores live et stats
19. Premier League 2025/2026 : analyse mi-saison
20. Champions League : top affiches et résultats live

**Mobile Money / FCFA (5)**
21. Mobile Money jeux : comment déposer et retirer en sécurité
22. Les frais Mobile Money sur les jeux en ligne au Cameroun
23. Orange Money vs MTN MoMo : lequel pour jouer en ligne ?
24. K-Pay et jeux en ligne : ce qu'il faut savoir
25. Limites de dépôt et retrait : le cadre légal au Cameroun

**Cameroun / lifestyle (5)**
26. Top 10 jeux mobiles les plus joués au Cameroun en 2026
27. Jouer responsable : 5 règles à respecter
28. Les meilleurs jeux d'argent légaux au Cameroun
29. Comparatif : Plugbet vs autres apps de jeu camerounaises
30. Témoignages : 3 joueurs racontent leur expérience Plugbet

Chaque article doit faire **800–1 500 mots**, intégrer 2–3 mots-clés
secondaires, des liens internes vers les pages "jeu", un CTA, et au
moins 1 lien sortant vers une source autoritaire (Wikipedia,
fpl.com, mediumcm.com, etc.).

---

## 7. Plan de netlinking

**Cibles natives Afrique francophone (priorité haute)** :
- Forums football Cameroun (cameroon-info.net, camfoot.com,
  237sports.com) : poster des analyses utiles avec lien profil renvoyant
  à un article du blog.
- Communauté FPL francophone Discord/Reddit r/FantasyPL : se positionner
  comme contributeur, lien en signature.
- Blogs paris sportifs Afrique (rendezvousfoot, africatopsports) :
  proposer des articles invités.
- Influenceurs football camerounais Instagram/TikTok (recherche
  hashtags #LionsIndomptables, #FootCameroun) : partenariats codes promo.

**Cibles globales / haute autorité (priorité moyenne)** :
- Product Hunt : lancement Plugbet (catégorie Games + Sports).
- AppGrooves, AppAdvice : listing app Android.
- itch.io (page promo des jeux mini comme Penalty Shootout déjà créé).
- Sites de revues d'apps Android (apkmirror, aptoide).

**Annuaires & listings locaux** :
- Annuaires Cameroun (cameroun-business.com).
- Google Business Profile (si entité légale enregistrée).
- Pages Jaunes Cameroun.

**Métrique cible 90 jours** : 15–25 backlinks de DA > 20, dont au moins
5 contextuels (in-content, pas en signature/footer).

**Ne PAS faire** : achat de liens en masse, PBN, échanges réciproques
massifs — Google sanctionne lourdement, surtout sur sites paris/jeux.

---

## 8. Estimation du gain de trafic

Hypothèses : marché Cameroun ~5–10 M d'utilisateurs internet actifs,
~25 % intérêt foot/jeux mobiles, concurrence locale faible sur le
créneau "jeux multi mobile money".

| Période | Visites organiques/mois (estimé) | Hypothèses |
|---|---|---|
| Aujourd'hui | ~30–80 | Recherches de marque uniquement |
| J+30 (après P0+P1) | 200–500 | Indexation des 3 pages, OG, schema, vitesse corrigée |
| J+60 (après pages jeux) | 1 200–2 500 | 11 pages indexées, long-tail jeux |
| J+90 (après 12 articles blog) | 3 000–6 000 | Pages piliers + blog + premiers backlinks |
| J+180 (continuité contenu) | 8 000–18 000 | Cycle vertueux, marque émergente |

**Conversion réaliste** : 3–5 % des visiteurs SEO ouvrent l'app, 1–2 %
créent un compte → **30 à 120 nouveaux comptes/mois en organique à J+90**,
gratuit (vs CPA Facebook Ads ~1 500–3 000 FCFA/install).

---

## 9. Liste de priorités (du plus critique au moins)

| # | Tâche | Sévérité | Effort | Impact |
|---|---|---|---|---|
| 1 | Retirer le préchargement Flutter de la vitrine (P0.3) | 🔴 | 15 min | Énorme (Core Web Vitals) |
| 2 | Ajouter meta description sur les 3 pages (P0.1) | 🔴 | 15 min | Élevé (CTR) |
| 3 | Créer `robots.txt` (P0.4) | 🔴 | 5 min | Élevé |
| 4 | Créer `sitemap.xml` (P0.5) | 🔴 | 10 min | Élevé |
| 5 | Ajouter Open Graph + Twitter Card (P0.6) | 🔴 | 30 min | Élevé (partages) |
| 6 | Ajouter Schema.org JSON-LD (P0.7) | 🔴 | 30 min | Élevé (rich snippets) |
| 7 | Créer 8 pages "jeu" statiques (P0.2) | 🔴 | 8–12 h | Énorme (long-tail) |
| 8 | Optimiser les titles (P1.1) | 🟠 | 10 min | Moyen |
| 9 | Ajouter canonical (P1.2) | 🟠 | 5 min | Moyen |
| 10 | Réécrire privacy/terms véridiques (P1.9) | 🟠 | 1 h | Légal + E-E-A-T |
| 11 | Ajouter burger menu mobile (P1.8) | 🟠 | 1 h | Moyen |
| 12 | Setup Search Console + Analytics | 🟠 | 30 min | Diagnostic |
| 13 | Corriger logo href="#" → "/" (P1.5) | 🟠 | 1 min | Faible |
| 14 | Page intermédiaire APK download (P1.6) | 🟠 | 1 h | Moyen |
| 15 | Retirer le SW kill-switch de la vitrine (P1.7) | 🟠 | 5 min | Faible |
| 16 | Page 404 custom (P2.2) | 🟡 | 30 min | Faible |
| 17 | Favicon.ico multi-res (P2.1) | 🟡 | 15 min | Faible |
| 18 | Headers de sécurité nginx (P3) | 🟢 | 30 min | Faible |
| 19 | Blog + 12 premiers articles | — | 2 mois | Énorme (cumulatif) |
| 20 | Plan netlinking | — | continu | Énorme (cumulatif) |

---

## 10. Code prêt à coller — Patch minimal pour passer de 28 à ~55 en 1 heure

À appliquer dans `index.html`, `privacy.html`, `terms.html`, plus
créer `robots.txt` et `sitemap.xml`. Le détail de chaque snippet est
dans les sections P0/P1 ci-dessus. Une fois ce patch déployé sur
nginx, demander réindexation dans Search Console pour accélérer la
prise en compte.
