# Diagnostic anonyme — v0.33.0

Source unique des rapports partageables : [privacy_diagnostics.dart](lib/features/diagnostics/privacy_diagnostics.dart). Interface [anonymous_diagnostics_screen.dart](lib/features/diagnostics/anonymous_diagnostics_screen.dart) et canal Kotlin fr.twittervideo.client/diagnostics.

## Cycle de vie

- Collecte automatique locale dès le lancement ; fenêtre glissante 300 000 ms, plafond 4 000 événements (les plus récents conservés), entretien toutes les 5 s.
- Persistance privée SharedPreferences sous anonymous_diagnostic_rolling_v1, écriture regroupée après une seconde et sérialisée, restauration des seuls événements récents au redémarrage.
- Paramètres → Diagnostic anonyme → Télécharger le diagnostic récent → Télécharger les 5 dernières minutes.
- Capturer le snapshot et les entrées correspondantes, écrire via Android, retirer seulement les entrées sauvegardées après confirmation, persister le journal réduit. Les événements reçus durant la sauvegarde restent pour le prochain export. En cas d'erreur de sauvegarde, le journal reste disponible.
- Android 10+ : MediaStore.Downloads avec IS_PENDING, nom twit-vid-anonyme.json (Android peut suffixer les doublons) ; aucun sélecteur de dossier. Android antérieur : répertoire externe de l'application. Effacer le journal manuellement n'efface pas les fichiers déjà téléchargés.
- Les fichiers enregistrés dans Téléchargements restent sous le contrôle de l'utilisateur. Aucun envoi automatique.

## Contrat de données

Format twit_vid_anonymous_diagnostics_v1 : app_version, window_seconds, elapsed_seconds, event_count, events_dropped_due_to_limit, privacy, summary et timeline. Entrées : elapsed_ms relatif à la fenêtre, event enum, count_bucket et duration_bucket facultatifs.

Quantités : zero, one_to_four, five_to_nineteen, twenty_plus. Durées : under_250ms, 250ms_to_1s, 1s_to_3s, 3s_to_6s, 6s_plus. Les événements AtTarget/BelowTarget distinguent le seuil 30 de la réserve ; twenty_plus seul ne suffit pas.

Les heures absolues nécessaires au stockage privé ne sortent jamais dans le JSON. Ne jamais exporter identifiants ou hashes de vidéos/compte, abonnements, hashtags, termes de recherche, URL, contenu, erreurs brutes, cookies, jetons ni identifiant de téléphone. AppLogger et debugPrint sont distincts, et potentiellement sensibles. Ne jamais les joindre à un rapport.

Erreurs réseau : enum fermé (auth HTTP 401/403, rate limit 429, serveur 500/502/503/504, autre, format invalide, timeout, erreur réseau). Ne pas transmettre le texte de l'exception au recorder. Un événement n'est pas une preuve que l'opération distante a abouti si l'API confirme seulement l'envoi.

## Tests et analyse

test/features/diagnostics/privacy_diagnostics_test.dart : démarrage auto, expiration, plafond, anonymat, restauration, purge après succès, conservation en cas d'échec, événements concurrents et persistance après redémarrage. Test manuel Android : sauvegarder deux fois, vérifier le dossier, redémarrer, vérifier que les anciens événements ne réapparaissent pas. Tester échec de stockage. La CI ne réalise pas ce test matériel.

Ne jamais déposer de diagnostics utilisateur dans le dépôt public. Documenter les métriques agrégées et leur limite, pas les traces individuelles.


## Évolution v0.34.0

Événements fermés audioMuted, audioUnmuted, audioApplyFailed ; durées bucketées sur searchFound/searchFailed. Un changement de préférence ne garantit pas que la piste audio contient du son. Aucun identifiant ou donnée audio exportée.
