# Limites et travaux à vérifier

État de référence : 28/11/2026, v0.33.0 publiée, CI réussie. Les observations historiques ci-dessous proviennent de rapports anonymes des versions précédentes et ne sont pas des mesures actuelles de v0.33.0. Aucun identifiant personnel ni trace brute.

| Sujet | État / preuve | Prochain contrôle |
| --- | --- | --- |
| Recherche X | Un échec sur une recherche dans un rapport v0.32.0. Les interfaces X non officielles changent ; FxEmbed peut renvoyer 503 ou 429. v0.33 ajoute catégories d'erreur et replis. | Tester recherche avec/sans session, plusieurs thèmes, profil @compte, pagination et retour du cache ; vérifier les catégories HTTP. Ne pas affirmer que l'accès X est réparé sans test réel. |
| Découverte de nouveaux auteurs | Trois relevés de découverte à zéro en v0.32.0. Cache et profils pertinents ajoutés en v0.33 ; le repli peut ramener des auteurs déjà connus. | Mesurer découverteDistinctAuthors, volume de rejets, source cache/profil et récurrence. Distinguer absence de candidats et mauvais classement. |
| Réserve vidéo | Stock ≥20 au début d'un rapport v0.32.0, 1–4 plus tard ; une actualisation vide et un échec de chargement. Cible 30, pas une garantie. | Sur plusieurs minutes, suivre AtTarget/BelowTarget, changements d'onglet et refus rapides. Vérifier que le provider n'est pas reconstruit inutilement. |
| Chromecast | 10/10 lancements signalés réussis, 13 commandes seek sans erreur dans un rapport v0.32.0 ; pas de fin naturelle concluante. | Vérifier position réellement atteinte, lecture/pause, passage automatique TV/téléphone, likes/dislikes sur le bon média, swipes rapides et plusieurs écrans. |
| Favoris anciens | Certaines anciennes entrées J’aime peuvent ne plus avoir d'URL/métadonnées récupérables. | Vérifier récupération via détail/profil et maintien du like si le média a disparu. |
| Diagnostic | v0.33.0 code et tests de purge intégrés ; export natif pas encore confirmé sur un téléphone par un rapport postérieur. Écriture privée best effort, stockage plein ou arrêt brutal possibles. | Export successif, redémarrage, échec disque ; contrôler que le journal exporté disparaît et que les nouveaux événements restent. |
| Durée et apprentissage | Durée inconnue validée par le lecteur ; temps de visionnage par incréments de 7 secondes, cumulé. Pas d'apprentissage de complétion Cast confirmé. | Mesurer les visionnages courts/longs, lectures répétées, Cast, effets de la blacklist et du dislike. |
| Publication | v0.30.0 avait un APK sans SHA-256 (upload 422), corrigé par relance. Workflow brouillon + vérification des assets depuis v0.31. | Ne pas contourner SHA-256 ; vérifier les deux assets et la signature stable. Une relance sur un tag déjà publié peut modifier ses assets. |

## Pistes non implémentées ou non validées

- Découverte réellement multi-sources et diversité durable sans dépasser les limites d'accès autorisé ; mieux distinguer score de pertinence, nombre d'auteurs et renouvellement.
- Mesure de confirmation distante du seek et du visionnage Cast sans export d'identité.
- Tests d'intégration Android/Chromecast ; vérifier le cycle complet export → purge → redémarrage.
- Éviter qu'un build de documentation ou une relance arbitraire republie les assets d'une version existante ; utiliser [RELEASE.md](RELEASE.md).

Ces pistes ne constituent pas des promesses de livraison. Attendre GO explicite du mainteneur avant une nouvelle série de modifications.
