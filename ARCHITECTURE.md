# Architecture et guide de reprise

Référence : v0.33.0, commit applicatif `1fae12397887fa30f2e68f19ef939d590de2bacc`, CI [46034662094](https://github.com/Gitskrap/twit-vid/actions/runs/46034662094) réussie. Flutter/Dart, Riverpod 3, media_kit, SQLite, SharedPreferences et Android natif Kotlin. Fork indépendant de XFlow. L'app n'est pas un client officiel X.

## Parcours de démarrage

```text
lib/main.dart
  -> WidgetsFlutterBinding / MediaKit / PrivacyDiagnostics.initialize
  -> TwitterAccount.init + Repository.database
  -> ProviderScope / XFlowApp
  -> BiometricGate / startup_update_check
  -> navigation Riverpod et écrans
```

L'identité Android est `fr.twittervideo.client`, namespace `com.alchemistaloha.xflow`, package Dart `xflow`. Ne pas renommer : compatibilité des données, imports et mises à jour signées.

## Carte du code

| Fichier / dossier | Responsabilité |
| --- | --- |
| lib/main.dart, lib/core/navigation/navigation_provider.dart | Onglets Vidéos, Abonnements, Hashtags, J’aime et navigation des écrans secondaires |
| lib/core/client/twitter_account.dart, account_provider.dart | Sessions X, comptes sauvegardés, session active |
| lib/core/client/twitter_client.dart | Requêtes X GraphQL, parsing, pagination, gestion du débit |
| lib/core/client/public_x_client.dart | FxEmbed public, sans cookies X ; recherche et profils |
| lib/core/database/repository.dart | SQLite, migrations, cache, historique, likes, métadonnées et requêtes |
| lib/core/models/tweet.dart | Données vidéo, auteur, durée, provenance, compteurs publics, temps visionné local |
| lib/features/feed/feed_provider.dart | AsyncNotifier, réserve, rafraîchissement, chargement progressif et récupération |
| lib/features/feed/local_recommendation_profile.dart | Pondération des thèmes et filtrage des réactions |
| lib/features/feed/fresh_video_queue.dart | Déduplication, diversité des auteurs et préservation de l'ordre |
| lib/core/client/discovery_engine.dart | Entrelacement, saturation, boost des abonnements peu vus |
| lib/features/feed/tiktok_feed_screen.dart | PageView vertical, index courant, réserve et préchauffage |
| lib/features/feed/local_video_reactions_provider.dart | Réactions privées, invalidation de la liste J’aime |
| lib/features/feed/liked_videos_screen.dart | Grille et lecteur des vidéos aimées |
| lib/features/search/video_search_screen.dart | Recherche X, repli public, cache, pagination, annulation logique |
| lib/features/feed/hashtag_feed_screen.dart et hashtag_provider.dart | Hashtags suivis, blacklist, lecture des résultats |
| lib/features/profile/ | Profil, grille et lecteur de compte |
| lib/features/player/player_pool_provider.dart et widgets/media_container.dart | Pool media_kit, lecture, validation des durées, observation du visionnage |
| lib/features/cast/ | Contrôle distant, file Cast, proxy MP4 Wi-Fi |
| lib/features/diagnostics/ | Journal strictement anonymisé |
| lib/features/update/ | Version, téléchargement vérifié et installation |
| android/app/src/main/kotlin/com/alchemistaloha/xflow/MainActivity.kt | Canaux diagnostics, mises à jour, volume Cast et pont Android |
| test/ | Tests unitaires Flutter et SQLite FFI |

## Circulation des vidéos

```text
Abonnements locaux + thèmes issus des préférences
  -> X (session active) / FxEmbed public / cache pertinent
  -> métadonnées Tweet
  -> filtres (vidéo, durée, réactions, blacklist, historique)
  -> déduplication et diversité
  -> SQLite puis file FeedState immuable
  -> PageView + pool de lecteurs
  -> observation locale du visionnage et réactions
```

Le préfixe de la file reste stable pendant les chargements ; ne réordonner que la nouvelle fin de file. La réserve vise 30 vidéos, sans garantie de disponibilité. Le fil conserve son provider via keepAlive, mais une dépendance observée peut encore provoquer une reconstruction.

## Données et confidentialité

- SQLite conserve cache vidéo, métadonnées, abonnements, compteurs, historique et réactions. Vérifier le schéma et les migrations de Repository avant toute modification ; aucun reset destructif.
- SharedPreferences conserve les réglages et le journal technique récent. Des timestamps privés sont nécessaires à la fenêtre glissante ; jamais dans l'export.
- Les likes/dislikes sont privés à l'app ; les compteurs affichés sont ceux de X. Les vidéos aimées conservent les métadonnées même lors de la purge, mais les liens peuvent expirer.
- Les sources distantes reçoivent les requêtes nécessaires (mots-clés, profils, authentification X pour le client X). Ne pas confondre confidentialité du diagnostic et anonymat de navigation.
- Le proxy Cast sert les octets vidéo au récepteur local, sans envoyer de cookie X à la TV.

## Conventions de reprise

Lire [AGENTS.md](AGENTS.md), puis [RECOMMENDATIONS.md](RECOMMENDATIONS.md), [CAST.md](CAST.md), [DIAGNOSTICS.md](DIAGNOSTICS.md) ou [RELEASE.md](RELEASE.md) selon le domaine. Les versions publiées et limites sont dans [CHANGELOG.md](CHANGELOG.md) et [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Les plans historiques dans docs/superpowers décrivent le fork d'origine, pas nécessairement le comportement actuel.


## Évolution v0.34.0 (en validation)

Le contrôle audio commun est dans video_audio_provider.dart et widgets/video_audio_button.dart, placé par media_container.dart hors des en-têtes des écrans. PlayerPoolNotifier applique l'état global et le relit après ouverture asynchrone. Le fil observe les signatures stables des abonnements/hashtags, la session et l'initialisation plutôt que l'ensemble des réglages UI ; les réglages réseau sont relus au chargement. Le client X mémorise la dernière méthode/opération de recherche valide et donne priorité aux demandes manuelles en attente, dans un budget de temps borné. Les demandes déjà en cours ne sont pas interrompues.
