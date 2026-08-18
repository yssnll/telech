# Telech — lecteur vidéo iOS autonome

Application Expo/React Native pour lire des vidéos MP4 et des playlists HLS (`.m3u8`) et les conserver hors ligne sur l’iPhone.

## Compilation automatique de l’IPA

La GitHub Action `Build iOS IPA` compile l’application sur macOS à chaque push sur `main` ou `ipa-autonome`, ou manuellement depuis l’onglet **Actions**.

Elle génère et publie `HLSVideoPlayer-unsigned.ipa` comme artefact GitHub Actions.

## Autonomie

- aucun backend ni API du projet ;
- aucune clé ou variable Replit nécessaire pour la build iOS ;
- téléchargement HLS réalisé directement par `AVAssetDownloadURLSession` ;
- lecture locale sans réseau après téléchargement.

Internet reste nécessaire pour ouvrir ou télécharger une URL vidéo la première fois.

## Build locale

Sur macOS avec Xcode et CocoaPods :

```bash
pnpm install
pnpm exec expo prebuild --platform ios
cd ios
pod install
open HLSVideoPlayer.xcworkspace
```

Dans Xcode, active la signature automatique avec ton équipe Apple, puis utilise **Product > Archive > Distribute App**.

Les détails sont dans [`IOS_BUILD.md`](./IOS_BUILD.md) et [`BUILD_IPA.md`](./BUILD_IPA.md).

Le dossier `dist/` contient également le ZIP complet du kit IPA autonome.
