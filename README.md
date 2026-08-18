# Telech — lecteur vidéo iOS autonome

Application Expo/React Native pour lire des vidéos MP4 et des playlists HLS (`.m3u8`) et les conserver hors ligne sur l’iPhone.

## Autonomie

- aucun backend ni API du projet ;
- aucune clé ou variable Replit nécessaire pour la build iOS ;
- téléchargement HLS réalisé directement par `AVAssetDownloadURLSession` ;
- lecture locale sans réseau après téléchargement.

Internet reste nécessaire pour ouvrir ou télécharger une URL vidéo la première fois.

## Générer l’IPA

Sur macOS avec Xcode et CocoaPods :

```bash
pnpm install
pnpm exec expo prebuild --platform ios
cd ios
pod install
open HLSVideoPlayer.xcworkspace
```

Dans Xcode, active la signature automatique avec ton équipe Apple, puis utilise **Product > Archive > Distribute App** pour exporter l’IPA ou l’envoyer vers TestFlight.

Les détails sont dans [`IOS_BUILD.md`](./IOS_BUILD.md) et [`BUILD_IPA.md`](./BUILD_IPA.md).

## Archive prête à récupérer

Le dossier `dist/` contient également le ZIP complet du kit IPA autonome.
