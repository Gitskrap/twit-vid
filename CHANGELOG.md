# Historique des versions — Twit Vid

Source : notes des [GitHub Releases](https://github.com/Gitskrap/twit-vid/releases), vérifiées le 28/11/2026. Les dates sont les dates UTC de publication. Les descriptions anciennes sont historiques et ne constituent pas les règles actuelles. Pour les versions antérieures à 0.16.0, voir [TWITTER-VIDEO.md](TWITTER-VIDEO.md) : il n'existe pas de release correspondante dans la liste vérifiée.

## Non publié

- Reprise documentaire : architecture, recommandations, Cast, diagnostics, limites, procédure de release et règles de maintenance. Aucun changement applicatif ni incrément de version.

## [v0.33.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.33.0) — 2026-11-27

Export direct des diagnostics dans Téléchargements, purge après sauvegarde, recherche et découverte plus robustes, diagnostics techniques anonymisés.

## [v0.32.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.32.0) — 2026-11-27

Cast synchronisé, contrôle distant de lecture, recommandations plus variées, réserve locale prioritaire, recherches temporisées et diagnostics anonymes enrichis.

## [v0.31.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.31.0) — 2026-11-26

Diagnostic anonyme automatique, export des cinq dernières minutes, conservation locale du journal récent et publication sécurisée de l’APK avec SHA-256.

## [v0.30.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.30.0) — 2026-11-25

Nouvel onglet J’aime local, vidéos favorites protégées du nettoyage du cache, miniatures de profil sans recadrage. APK signé et SHA-256.

## [v0.29.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.29.0) — 2026-11-25

Fluidité du fil : réserve cible de 30 vidéos, préchargement des trois suivantes, détection des lectures bloquées et passage sécurisé à la suivante. Diagnostic anonyme enrichi : délai de démarrage, réserve et erreurs techniques génériques. APK signé et SHA-256.

## [v0.28.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.28.0) — 2026-11-19

Fiabilité du fil Vidéos : mémorisation des recommandations effectivement regardées pour éviter les répétitions, chargements initiaux progressifs, rechargements du fil moins fréquents, conservation de la vidéo visible lors des rafraîchissements, exclusion des doublons et des vidéos de 15 s ou moins, pagination et recherches contrôlées. 👎 : diagnostic anonyme du passage à la suivante. Préférences, blacklist, Cast et mises à jour intégrées conservés. APK signé et SHA-256.

## [v0.27.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.27.0) — 2026-11-18

Diagnostic volontaire et anonyme : enregistrer l’utilisation durant plusieurs minutes, arrêter, consulter le rapport puis le partager depuis Android. Événements techniques sans identifiant de vidéo, nom de compte, abonnement, hashtag, requête, URL ni erreur brute. Chronologie relative, données en mémoire et aucun envoi automatique. APK signé et SHA-256.

## [v0.26.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.26.0) — 2026-11-18

Mise à jour depuis l’application : détection automatique des nouvelles GitHub Releases après déverrouillage, écran Mises à jour, téléchargement de l’APK avec progression et vérification SHA-256, puis installation Android avec confirmation. Les données restent en place, signature permanente conservée. Aucun token GitHub embarqué.

## [v0.25.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.25.0) — 2026-11-10

Correction de la recherche et du clic sur hashtag : source publique et cache en secours. Le fil Vidéos utilise des pages de découvertes successives et évite les vidéos déjà vues. Cast enchaîne automatiquement sur la vidéo suivante lorsque le précédent média est terminé, tant que l’application et la connexion Cast sont actives. APK ARM64 signé.

## [v0.24.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.24.0) — 2026-11-10

Son coupé par défaut au lancement avec bouton pour l’activer. Plein écran conservé pendant les changements de vidéo. Blacklist de hashtags pour exclure les recommandations. Bouton Je n’aime pas immédiat : masque la vidéo, passe à la suivante et réduit les suggestions du même style. APK ARM64 signé.

## [v0.23.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.23.0) — 2026-11-10

Fil Vidéos recommandé d’après les J’aime locaux, les vidéos réellement regardées, les abonnements et les hashtags enregistrés. Clips de plus de 15 secondes uniquement : durée X ou vérification par le lecteur. APK ARM64 signé, téléchargement direct.

## [v0.22.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.22.0) — 2026-11-10

Les hashtags enregistrés dans l’onglet Hashtags améliorent les recommandations Vidéos, avec les abonnements et les J’aime locaux. Les Je n’aime pas continuent à écarter les thèmes rejetés. APK Android ARM64 signé, téléchargement direct.

## [v0.21.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.21.0) — 2026-11-10

J’aime et Je n’aime pas 100% locaux à Twitter vidéo, sans action sur X. Préférences persistantes, vidéos similaires influencées par les likes et suppression des thèmes rejetés. Réinitialisation possible dans Stockage. APK ARM64 signé, téléchargement direct.

## [v0.20.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.20.0) — 2026-11-10

L’en-tête affiche désormais Session X : @compte à la place du logo Twitter vidéo ; suppression du badge de session dupliqué sur chaque vidéo. Les likes utilisent la session X active. APK ARM64 signé, téléchargement direct.

## [v0.19.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.19.0) — 2026-11-10

Barre de progression vidéo tactile avec glissement et temps lisibles. Badge distinct pour la session X active et la provenance Cache/Public/@compte, sans recouvrir les réglages. APK ARM64 signé, téléchargement direct.

## [v0.18.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.18.0) — 2026-11-10

Correction du Cast (widget ref), badge Cache/compte dans la fiche vidéo et découvertes similaires aux abonnements locaux, activables dans les réglages. APK ARM64 signé, téléchargement direct.

## [v0.17.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.17.0) — 2026-11-09

Fil Vidéos limité aux abonnements locaux ; badge du compte X ou de la source publique utilisée. APK ARM64 signé, téléchargement direct.

## [v0.16.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.16.0) — 2026-11-09

APK Android ARM64 signé. Téléchargement direct du .apk (pas de fichier ZIP).

## Versions anciennes (avant 0.16.0)

Voir les sections historiques de [TWITTER-VIDEO.md](TWITTER-VIDEO.md), les [notes anciennes](docs/update/) et l'historique Git. Ne pas inventer de versions, dates ou validation absentes des sources.
