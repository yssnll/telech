# Kit IPA autonome

Le projet est autonome : il ne contacte aucun backend de ce projet et ne
demande aucune variable d’environnement pour produire l’application iOS.

## Générer l’IPA

Sur macOS :

```bash
pnpm install
pnpm exec expo prebuild --platform ios
cd ios
pod install
open HLSVideoPlayer.xcworkspace
```

Dans Xcode, active la signature automatique avec ton équipe Apple, puis fais
**Product > Archive** et **Distribute App**.

## Utilisation hors ligne

L’iPhone doit avoir Internet pour ouvrir ou télécharger une URL vidéo. Après le
téléchargement, la vidéo est stockée localement et sa lecture ne demande plus
de réseau ni de serveur.