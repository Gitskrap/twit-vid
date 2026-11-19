# <img src="assets/app_icon.png" alt="Icône de Twitter vidéo" width="40" /> Twit Vid — Twitter vidéo

**Twit Vid** est un client Android open source, développé en **Flutter**, pour regarder les **vidéos publiques de X (Twitter)** dans un fil vertical, sans l'interface classique du réseau social.

> **Dépôt GitHub :** `Gitskrap/twit-vid`  
> **Nom sur le téléphone :** **Twitter vidéo**  
> **Dernière version publiée vérifiée :** [v0.28.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.28.0)  
> **Téléchargement Android :** [APK ARM64 signé](https://github.com/Gitskrap/twit-vid/releases/download/v0.28.0/Twitter-video-0.28.0-arm64.apk)

Ce projet est un **fork indépendant de [XFlow](https://github.com/Alchemist-Aloha/xflow)**. Il n'est ni développé ni approuvé par X Corp.

## Fonctionnalités

- **Fil plus stable (0.28.0)** : le lecteur conserve les vidéos visibles pendant les rafraîchissements, évite de reproposer les découvertes déjà regardées, déduplique les médias et recherche de nouveaux résultats sans répéter inutilement les mêmes pages.
- **Fil « Vidéos » personnalisé** : recommandations issues des **J’aime enregistrés dans l’application**, des vidéos effectivement regardées, des comptes suivis localement et des hashtags favoris.
- **Vidéos de plus de 15 secondes uniquement** dans le fil principal ; les durées inconnues sont vérifiées par le lecteur lorsqu'il le peut.
- **J’aime et Je n’aime pas privés à l’application** : aucune action de like/dislike envoyée au compte X. Un 👎 masque la vidéo et réduit les propositions similaires.
- **Compteurs publics de X** : le nombre de J’aime affiché reste celui communiqué par X, et non celui des réactions locales.
- **Hashtags favoris et blacklist** : suivre un thème pour améliorer les recommandations, ou exclure les vidéos portant certains hashtags.
- **Abonnements locaux** : ajouter ou retirer des comptes publics dans l'application sans les suivre sur X ; l'accès aux vidéos dépend toutefois des sources disponibles.
- **Recherche de vidéos et de hashtags** : tentative par X, source publique de secours, puis résultats déjà présents dans le cache si le réseau ou les services échouent.
- **Lecteur vertical** : défilement fluide, barre de progression manipulable, son coupé au démarrage, mode paysage et plein écran conservé lors du changement de vidéo.
- **Diagnostic anonyme sur demande** : enregistrement d'une session d'utilisation, consultation du rapport détaillé puis partage volontaire. Aucun identifiant de vidéo, compte, abonnement, hashtag, mot-clé recherché ou URL n'est enregistré dans ce rapport.
- **Mises à jour intégrées** : après déverrouillage, l'application vérifie automatiquement les nouvelles GitHub Releases ; une page dans les paramètres permet aussi la vérification manuelle, le téléchargement avec progression et l'installation confirmée par Android. Les APK sont contrôlés par SHA-256 avant installation.
- **Google Cast (bêta)** : envoi de la vidéo au téléviseur via un relais Wi-Fi local, contrôle du volume et tentative de lecture automatique de la suivante.
- **Cache et historique locaux** : mémorisation des vidéos vues pour limiter les répétitions entre les sessions.

Les fonctionnalités dépendant de X ou d'un service public tiers peuvent être limitées, interrompues ou retourner des résultats incomplets. L'enchaînement Cast reste à valider selon les téléviseurs et les formats vidéo.

## Diagnostic de fiabilité du fil (0.28.0)

Les rapports anonymes disposent de nouveaux événements techniques : `dislikeAdvanceRequested`, `dislikeAdvanceConfirmed`, `dislikeAdvanceNoNext`, `feedRepeatedCandidatesFiltered`, `feedNoFreshCandidates`, `feedRefreshCoalesced` et `feedLoadCooldown`. Ils enregistrent des catégories, quantités regroupées et temps relatifs uniquement — **jamais** d'identifiants de vidéos, de comptes, de hashtags ou de recherche.

## Installer sur Android

1. Ouvrir la [page des versions](https://github.com/Gitskrap/twit-vid/releases/latest).
2. Télécharger le fichier **`Twitter-video-…-arm64.apk`** de la dernière version.
3. L'ouvrir sur un téléphone Android ARM64 et autoriser l'installation depuis cette source si Android le demande.
4. Pour les prochaines mises à jour, installer le nouvel APK **par-dessus l'application existante** : le paquet Android et la signature doivent rester identiques.

**Version actuelle :** [Twitter-video-0.28.0-arm64.apk](https://github.com/Gitskrap/twit-vid/releases/download/v0.28.0/Twitter-video-0.28.0-arm64.apk).

L'accès à un compte X est facultatif pour les fonctions locales, mais certaines vidéos ou certaines recherches peuvent nécessiter une session X valide.

## Mises à jour dans l'application

À partir de la **0.26.0**, Twit Vid vérifie les nouvelles versions lors de son démarrage (après le déverrouillage biométrique). Si une mise à jour est disponible, une fenêtre propose **Plus tard** ou **Mettre à jour**. Une vérification manuelle reste accessible dans **Paramètres → Mises à jour de l’application**.

Le téléchargement utilise les fichiers publics de [GitHub Releases](https://github.com/Gitskrap/twit-vid/releases/latest). Un fichier `.sha256` est fourni avec chaque nouvel APK ; l'application vérifie son intégrité avant de demander l'installation à Android. Il peut être nécessaire d'autoriser l'installation depuis cette application lors de la première mise à jour.

**Aucun token GitHub privé n'est stocké dans l'APK.** Le dépôt étant public, le contrôle des versions ne nécessite pas de secret personnel. Les secrets de **signature Android** (`ANDROID_KEYSTORE_BASE64` et `ANDROID_SIGNING_PASSWORD`) restent sur GitHub Actions et doivent être conservés afin de permettre une installation par-dessus la version précédente.

L'installation n'est pas silencieuse : **Android demande une confirmation**. Les données de l'application sont conservées si l'identifiant Android et la clé de signature restent identiques.

## Développement

**Prérequis :** Flutter ≥ 3.44.0, Dart ≥ 3.12.0 et JDK 17 pour Android. La CI utilise Flutter 3.47.6.

```bash
git clone https://github.com/Gitskrap/twit-vid.git
cd twit-vid
flutter pub get
flutter analyze
flutter test
flutter run
```

Pour générer un APK Android local :

```bash
flutter build apk --release --target-platform android-arm64
```

La génération **release** demande les informations de signature privée configurées dans `android/key.properties`. Le dépôt ne contient ni la clé ni ses mots de passe. La [CI Android](.github/workflows/twitter-video-android.yml) utilise des secrets GitHub pour signer et publier les APK avec une clé stable.

**Important :** le nom interne du package Flutter reste `xflow` et le namespace Android historique reste en place pour préserver les imports et la compatibilité. Le nom public du dépôt et celui de l'application sont indépendants de ces identifiants techniques. Le paquet Android installé est `fr.twittervideo.client`.

## Organisation du code

| Chemin | Rôle |
| --- | --- |
| `lib/features/feed/` | Fil Vidéos, hashtags, réactions et recommandations |
| `lib/features/search/` | Recherche de vidéos |
| `lib/features/cast/` | Google Cast et relais local |
| `lib/features/player/` | Lecture vidéo, barre de progression et audio |
| `lib/features/subscriptions/` | Abonnements enregistrés sur le téléphone |
| `lib/core/` | Clients X/publics, modèles et base de données |
| `test/` | Tests automatiques |
| `TWITTER-VIDEO.md` | Historique technique des anciennes versions |

## Tester le fonctionnement avec un rapport anonyme

À partir de **0.27.0**, ouvre **Paramètres → Diagnostic anonyme → Démarrer le diagnostic**. Utilise normalement le fil Vidéos, la recherche, les hashtags, les réactions et le Cast pendant plusieurs minutes. Retourne ensuite dans l'écran de diagnostic : appuie sur **Arrêter l’enregistrement**, puis sur **Afficher le rapport complet** pour vérifier son contenu avant de choisir **Partager le rapport anonymisé**. Le bouton **Effacer les données du diagnostic** supprime la session et son fichier temporaire.

**La collecte est désactivée par défaut.** Le journal exporté est séparé des logs techniques bruts ; il contient uniquement un nombre limité d'événements issus d'une liste fermée, des durées relatives depuis le début de la session et des quantités regroupées en tranches. Il ne contient **aucun identifiant ni hash** de publication/vidéo/compte, aucun abonnement, hashtag, texte saisi, URL, message d'erreur brut, cookie, token ou horodatage absolu. Aucune donnée n'est envoyée automatiquement : toi seul choisis si et comment partager le rapport. Les détails techniques non anonymisés visibles dans les anciens logs ne doivent pas être partagés.

## Confidentialité et limites

Les J’aime, Je n’aime pas, abonnements et listes de hashtags sont conservés **localement** dans l'application. Les mots-clés utilisés pour récupérer les vidéos sont envoyés aux services de recherche sollicités ; ce n'est donc **pas** un mode de navigation totalement hors ligne. Le Cast peut transmettre le flux vidéo par le réseau local, sans dupliquer l'écran du téléphone.

Le projet utilise des interfaces **non officielles** de X et peut être affecté par leurs restrictions, des liens vidéo temporaires ou les limites de Google Cast.

## Licence et crédits

Projet distribué sous licence **MIT**, voir [LICENSE](LICENSE). Fork de [XFlow](https://github.com/Alchemist-Aloha/xflow) ; une partie de la couche de connexion et de données provient également de [Squawker](https://github.com/j-fb/squawker). Merci aux contributeurs des projets d'origine.

Les contributions et signalements de bugs sont bienvenus via les [issues GitHub](https://github.com/Gitskrap/twit-vid/issues).
