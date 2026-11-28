# Compilation, signature, publication et mise à jour

Référence vérifiée 28/11/2026 : v0.33.0, APK ARM64 et SHA-256 présents, [CI 46034662094](https://github.com/Gitskrap/twit-vid/actions/runs/46034662094) successful. Dépôt public Gitskrap/twit-vid. Procédure réelle dans [.github/workflows/twitter-video-android.yml](.github/workflows/twitter-video-android.yml), seule CI Android canonique ; release.yml est héritée.

## Préparer une version

1. Lire AGENTS.md et les limites, attendre GO si une série de retours est en attente.
2. Relever version et build dans pubspec.yaml, latest release et état de master. Pour une version applicative, incrémenter pubspec, app_version du rapport diagnostic et attentes de tests, paramètres --build-name / --build-number, noms APK/checksum/tag et notes du workflow.
3. Mettre à jour CHANGELOG.md, TWITTER-VIDEO.md, README et docs concernées. Préférer une branche/PR et fusion après revue ; ne pas publier avant validation. Ne jamais modifier les secrets.
4. CI : Flutter 3.47.6, JDK 17, flutter pub get, flutter analyze --no-fatal-infos --no-fatal-warnings, liste ciblée de tests dans le workflow, build release ARM64, artefact et publication. Le test complet flutter test est recommandé localement ; ne pas confondre suite ciblée CI et tous les tests possibles.

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --target-platform android-arm64
```

## Signature permanente

Android application ID fr.twittervideo.client et même clé à chaque version. Secrets GitHub Actions : ANDROID_KEYSTORE_BASE64 et ANDROID_SIGNING_PASSWORD. La CI reconstruit android/twitter-video-release.p12 et android/key.properties (alias twittervideo, mots de passe fournis via secrets), permissions restrictives, suppression des fichiers temporaires en fin de job. Ne jamais demander, afficher, committer ou embarquer les valeurs. Si la clé est perdue, l'installation par-dessus l'app existante peut devenir impossible.

## Publication

Sur master ou workflow_dispatch, le workflow construit et nomme Twitter-video-X.Y.Z-arm64.apk, génère le fichier .sha256 correspondant et téléverse les deux dans l'artefact GitHub Actions (30 jours). Les PR ne publient pas de release. Il crée un tag/release en brouillon si absent, téléverse chaque asset avec jusqu'à 3 tentatives, vérifie les deux noms et publie le brouillon. Une version déjà existante est susceptible d'être remplacée par --clobber : ne pas déclencher inutilement une nouvelle build sur un tag déjà publié.

Vérifier :
```bash
gh run list --workflow twitter-video-android.yml --branch master
gh run view <run-id>
gh release view vX.Y.Z --json tagName,isDraft,assets,url
gh release download vX.Y.Z -p 'Twitter-video-*-arm64.apk*'
sha256sum -c Twitter-video-X.Y.Z-arm64.apk.sha256
```

Si possible, contrôler aussi la signature avec apksigner verify --print-certs et comparer le certificat à une version installable précédente. Ne déclarer disponible qu'après vérification du résultat CI, du bon tag publié et des deux assets. Si erreur 422 ou fichier absent, examiner les logs, relancer uniquement les jobs échoués si pertinent, vérifier les assets. Ne pas désactiver le checksum pour contourner une publication incomplète.

## Mise à jour intégrée

lib/features/update/app_update_service.dart : GET public https://api.github.com/repos/Gitskrap/twit-vid/releases/latest ; comparaison des versions, sélection du nom APK attendu et du checksum, validation des URLs HTTPS GitHub du dépôt, téléchargement en cache privé, SHA-256 calculé pendant le streaming, rejet si absent ou différent, appel natif d'installation. startup_update_check déclenche la vérification après déverrouillage. Écran Paramètres → Mises à jour permet vérification manuelle et progression. Android affiche sa confirmation normale, pas d'installation silencieuse. Pas de token GitHub dans l'APK : seuls les secrets de signature restent dans Actions.

## Modifications documentaires

Ne pas incrémenter pubspec/version pour du Markdown seul. Le workflow actuel déclenche les pushes master, donc utiliser un commit purement documentaire avec le marqueur [skip ci] pour éviter le remplacement du même APK. Ne pas utiliser ce marqueur pour une modification applicative ou de workflow. Vérifier ensuite que la dernière release n'a pas changé. Renseigner les résultats de validation et les limites dans KNOWN_ISSUES.md ; ne jamais prétendre qu'un test matériel a été exécuté sans preuve.
