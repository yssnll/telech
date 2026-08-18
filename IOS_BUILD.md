# Construire l’IPA iOS autonome

Ce dossier contient uniquement l’application mobile et son module Swift local
`modules/offline-hls`. Il n’y a **aucune API du projet, aucun serveur et aucune
clé à configurer** pour construire l’application.

Le téléchargement HLS utilise directement `AVAssetDownloadURLSession`, le
service natif d’iOS. Une vidéo téléchargée est enregistrée dans le stockage
privé de l’iPhone et peut ensuite être lue sans réseau. Le lien source doit
toutefois être accessible sur Internet au moment de la lecture ou du
téléchargement initial.

Expo Go et l’aperçu web peuvent lire un flux, mais le téléchargement HLS en
arrière-plan nécessite la vraie build iOS autonome.

## Depuis le ZIP, sur un Mac

Pré requis : macOS, Xcode installé, CocoaPods et Node.js. Un compte Apple
Developer est nécessaire pour installer l’IPA sur un iPhone ou la distribuer
via TestFlight.

```bash
cd hls-video-player
pnpm install
pnpm exec expo prebuild --platform ios
cd ios
pod install
open HLSVideoPlayer.xcworkspace
```

Dans Xcode :

1. Sélectionner le projet `HLSVideoPlayer`, puis la cible `HLSVideoPlayer`.
2. Dans **Signing & Capabilities**, choisir ton équipe Apple Developer et
   laisser la signature automatique activée.
3. Vérifier l’identifiant `com.anonymous.hls-video-player` ou le remplacer par
   un identifiant dont tu es propriétaire.
4. Choisir **Any iOS Device (arm64)**.
5. Utiliser **Product > Archive**.
6. Dans l’Organizer, choisir **Distribute App** pour exporter l’IPA ou l’envoyer
   vers TestFlight.

Le dossier `ios/` est généré par `expo prebuild` et n’est volontairement pas
inclus dans le ZIP : il dépend de Xcode et de la machine qui signe
l’application.

## Compilation automatique avec GitHub Actions

Le fichier `.github/workflows/build-ios-ipa.yml` compile automatiquement
l’application sur un runner macOS lorsque la branche `main` ou `ipa-autonome`
est mise à jour. Il peut aussi être lancé manuellement depuis l’onglet
**Actions** avec **Run workflow**.

La workflow :

1. installe Node.js, pnpm et les dépendances JavaScript ;
2. génère le projet iOS avec Expo ;
3. installe les dépendances CocoaPods ;
4. archive l’application en Release avec Xcode ;
5. crée `HLSVideoPlayer-unsigned.ipa` ;
6. publie l’IPA dans les **Artifacts** du run GitHub Actions.

Cette version est compilée sans signature Apple afin de ne demander aucun
certificat ou secret Apple dans GitHub. Une IPA non signée ne peut pas être
installée directement sur un iPhone ; elle doit ensuite être signée avec ton
équipe Apple dans Xcode ou via une workflow de signature dédiée.

## Ce qui est inclus

- l’interface du lecteur vidéo ;
- la lecture directe des fichiers MP4 et des playlists `.m3u8` ;
- l’historique local ;
- l’onglet **Hors ligne** ;
- le module Swift de téléchargement HLS en arrière-plan ;
- la gestion du retour d’iOS après un téléchargement en arrière-plan ;
- les icônes et la configuration Expo nécessaires à la build.

## Limites des flux

Les flux chiffrés, les liens expirés et les vidéos protégées par une page web ou
une authentification externe peuvent refuser le téléchargement direct. Cela
vient du site source et ne nécessite pas l’ajout d’une API dans l’application.

La compilation/signature finale nécessite macOS et Xcode ; `xcodebuild` n’est
pas disponible dans l’environnement Linux.