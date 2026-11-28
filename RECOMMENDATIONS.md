# Recommandations — comportement réel v0.33.0

Sources principales : [local_recommendation_profile.dart](lib/features/feed/local_recommendation_profile.dart), [feed_provider.dart](lib/features/feed/feed_provider.dart), [fresh_video_queue.dart](lib/features/feed/fresh_video_queue.dart), [similar_video_discovery.dart](lib/features/feed/similar_video_discovery.dart). Algorithme heuristique local ; pas de modèle IA entraîné ni de classification visuelle du contenu.

## 1. Profil des intérêts

Les légendes fournissent hashtags normalisés et mots de 4–30 caractères, hors URL, mentions et mots génériques. Les sujets provenant des abonnements sont d'abord extraits et classés ; au plus 8 contribuent au score final.

| Signal | Points ajoutés |
| --- | --- |
| Sujet issu des vidéos des abonnements | +2 par sujet sélectionné |
| Hashtag suivi explicitement | +6 |
| Hashtag d'une vidéo aimée | +8 |
| Mot d'une vidéo aimée | +3 |
| Hashtag visionné, proportion <40 % | +2 |
| Hashtag visionné, proportion 40–79 % | +4 |
| Hashtag visionné, proportion ≥80 % | +7 |
| Mot visionné | +1, ou +2 si proportion ≥80 % |

Le temps significatif est enregistré par incréments de 7 secondes de lecture contiguë, en ignorant les grands sauts de position. Historique récupéré via Repository (40 vidéos récentes par défaut), trois exemples visionnés au maximum par auteur dans le calcul. Lorsque durée ou temps est inconnu, ratio de repli 0,5. Le temps stocké peut être cumulé sur plusieurs lectures : ce ratio est un proxy, pas une mesure parfaite de complétion individuelle.

Blacklist prioritaire ; hashtags issus des dislikes exclus des sujets ; mots rejetés supprimés si score ≤8. Classement décroissant par score, puis ordre lexical. Le fil demande jusqu'à 12 sujets et fait tourner le point de départ.

## 2. Candidats et récupération

- Fil de départ : cache éligible, limité à 45 vidéos ; récupération réseau en parallèle du rendu.
- Sources : abonnements locaux, recherche X authentifiée (Latest), FxEmbed public si échec/absence, puis cache et profils pertinents en secours.
- Par appel de découverte : jusqu'à 2 thèmes effectivement interrogés, 35 candidats demandés par thème, curseurs mémorisés, cooldown de 10 minutes si page épuisée. Les erreurs publiques temporisent le thème (2 minutes) ; 429/503 temporisent la recherche publique (10 minutes).
- Si moins de 20 candidats acceptés : chercher parmi 300 candidats non vus du cache correspondant aux thèmes.
- Si moins de 10 : jusqu'à trois profils publics de créateurs précédemment aimés/regardés, hors abonnements locaux, rotation/cooldown 5 minutes ; ne garder que les vidéos dont la légende correspond aux thèmes.
- Choisir jusqu'à 30 découvertes ; les enregistrer avant exposition, puis marquer les premières vues. Le repli par profil ne découvre pas nécessairement de nouveaux auteurs : il augmente la disponibilité de contenu pertinent.
- En cas de stock étroit, le cache thématique peut fournir des découvertes même avec des abonnements. Aucun ajout de contenu arbitraire ni contournement des restrictions de source.

## 3. Filtres

Vidéo et URL utilisable, durée strictement supérieure à 15 s dans le fil principal (durée inconnue validée par le lecteur), exclusion de la blacklist et du dislike exact, similarités négatives : hashtag commun ou au moins deux mots communs, ou un seul mot long (≥7 caractères) dans une légende courte. Un like exact peut outrepasser les similarités négatives, jamais la blacklist. Ne pas réintroduire les IDs vus ; dédupliquer ID, mediaKey et chemin URL sans signature éphémère.

## 4. Diversité et réserve

`diversifyAuthors` minimise, parmi les candidats restants, la pénalité 3 × occurrences de l'auteur dans les six derniers emplacements + 10 si auteur identique au précédent. Normalisation des handles, maintien du préfixe, pas de quota dur si peu d'auteurs disponibles. `mixRelatedVideos` alterne par défaut abonnement/découverte (intervalle 1), puis peut compléter avec des découvertes ; le mélange réel dépend des sources et de la disponibilité. Les réglages de saturation et le boost de comptes peu vus s'appliquent également à certains chemins. Aucun ratio 40/25/25/10 n'est implémenté comme quota.

Cible 30 vidéos en réserve, préchauffage courant + trois suivantes, maintenance toutes les 5 s lorsque le fil principal est actif. Charger d'abord le cache, puis le réseau, respecter coalescence et cooldown (25 s en cas de manque de résultats/échec). Ne jamais annoncer que 30 sont garanties.

## 5. Évaluation et tests

Événements anonymes : feedReserveSample, feedReserveAtTarget, feedReserveBelowTarget, feedReserveEmpty, feedDistinctAuthors (fenêtre de 20 candidates), discoveryDistinctAuthors, discoveryTopicCount, discoveryCandidatesRejected, discoveryCacheFallback, discoveryProfileFallback, feedRepeatedCandidatesFiltered, feedNoFreshCandidates.

Un bucket five_to_nineteen ne prouve pas une diversité suffisante ; les commandes Cast ne mesurent pas le temps réellement visionné sur TV. Voir [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Tests : fresh_video_queue_test, similar_video_discovery_test, local_recommendation_profile_test, watched_video_recommendations_test, followed_hashtag_recommendations_test, hashtag_blacklist_test, viewed_video_ids_test, discovery_playback_persistence_test et feed_pagination_cursor_test. Tous sous test/ ; liste CI dans [RELEASE.md](RELEASE.md).


## Évolution v0.34.0

Le fil n'observe plus les modifications générales des réglages UI pour reconstruire la file ; il relit les réglages au chargement et conserve les dépendances de préférences/sources pertinentes. La cible de 30 et les filtres restent inchangés. Les paramètres de récupération sont appliqués aux prochains chargements ou à une actualisation explicite.
