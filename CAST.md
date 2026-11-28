# Google Cast — fonctionnement et reprise

Référence v0.33.0. Code : [cast_video_button.dart](lib/features/cast/cast_video_button.dart), [cast_remote_controls.dart](lib/features/cast/cast_remote_controls.dart), [cast_autoplay_queue.dart](lib/features/cast/cast_autoplay_queue.dart), [local_video_proxy.dart](lib/features/cast/local_video_proxy.dart), MainActivity.kt.

## Démarrage et transport

Le bouton Cast ouvre le sélecteur de récepteur Google Cast. Le notifier ActiveCastTweetNotifier conserve récepteur, qualité, playlist, IDs déjà castés, session média et états de chargement/avancement. Une vidéo X est choisie parmi les MP4 HTTPS vidéo.twimg.com, avec repli qualité. Le relais LAN éphémère sert les octets MP4 et les Range HTTP ; pas de duplication d'écran, texte de tweet ou cookie transmis au téléviseur.

Le client attend une session connectée puis envoie LOAD. Le succès nécessite le statut playing associé à l'URL attendue ET à une nouvelle session média ; vérification de l'état courant puis attente du flux (25 s). L'identifiant actif change après confirmation, pas au moment de l'envoi.

## Téléphone comme télécommande

Pendant Cast, TiktokMediaContainer affiche le poster et les commandes distantes ; le lecteur local est mis en pause. CastRemoteControls lit position, durée et état du client distant toutes les 500 ms. Seek à la fin du glissement ; play/pause sur le client Google Cast, pas media_kit. Boutons physiques de volume via le canal natif Android. Si la durée distante manque, utiliser la durée connue de la vidéo. Ne pas confondre une commande envoyée avec une position confirmée sur TV.

```text
Sélection téléphone -> selectFromPhone -> pendingSelection -> LOAD
TV playing confirmé -> activeCastTweetProvider -> écran aligné sur la vidéo
TV IDLE + FINISHED de la session active -> prochaine candidate -> LOAD
```

L'écran visible fournit la file : fil principal, recherche, hashtags, profil ou favoris. Les écouteurs synchronisent les pages quand l'identifiant est présent dans leur liste. Une nouvelle sélection peut superséder une ancienne via génération et sélection en attente. Ne pas déclencher un nouveau LOAD à cause d'un saut de page de synchronisation.

## Fin de lecture

`isConfirmedCastFinish` exige : aucun chargement en cours, lecture préalablement confirmée, session attendue non nulle et égale à celle du statut, IDLE et raison FINISHED. Consommer une fin une seule fois ; ignorer pause, buffering, STOP, anciennes sessions. nextCastVideo filtre non-vidéos, URL absente, clips ≤15 s connus et IDs déjà castés. La recherche de candidats supplémentaires via le fil principal est limitée au contexte home. Arrêt explicite et déconnexion doivent fermer le proxy et remettre l'état à zéro.

## Diagnostic et tests

castPlayStarted/Succeeded/Failed, castVideoFinished, castAutoNextStarted/Succeeded/Empty/Failed, castPhoneSelection/Failed, castPhoneAligned, castSeekCommand, castPlayPauseCommand, castControlFailed, castDisconnected/Stopped. Aucun identifiant ou URL dans l'export.

Test automatique : test/features/cast/cast_autoplay_queue_test.dart, cast_quality_test.dart. Ces tests ne remplacent pas un vrai Chromecast.

Checklist matérielle :
- Caster depuis chaque écran ; vérifier titre/poster et réactions sur la même vidéo.
- Seek avant/arrière et pause/reprise depuis le téléphone et la TV ; vérifier la position réellement atteinte.
- Attendre une fin naturelle sans toucher au téléphone : TV et téléphone passent au même média.
- Swipes rapides, dislike, dernière vidéo, passage à un autre onglet, retour, déconnexion/reconnexion ; aucune lecture fantôme ni boucle.
- Tester réseau Wi-Fi instable et variantes MP4, volume physique et sortie du Cast.

État : les diagnostics v0.32.0 rapportaient 10 lancements réussis et 13 commandes seek sans erreur, mais aucun enchaînement naturel concluant. Rester prudent : [KNOWN_ISSUES.md](KNOWN_ISSUES.md).
