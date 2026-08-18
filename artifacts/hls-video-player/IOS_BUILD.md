# Construire et signer l’application iOS

Le dossier `ios/` a été généré à partir de la configuration Expo du projet. Il contient le projet Xcode et le fichier Swift de démarrage de l’application.

## Sur un Mac avec Xcode

Depuis la racine du dépôt :

```bash
pnpm install
cd artifacts/hls-video-player
npx pod-install ios
open ios/HLSVideoPlayer.xcworkspace
```

Dans Xcode :

1. Sélectionner le projet `HLSVideoPlayer`, puis la cible `HLSVideoPlayer`.
2. Dans **Signing & Capabilities**, choisir ton équipe Apple Developer.
3. Remplacer `com.anonymous.hls-video-player` par ton propre Bundle Identifier si nécessaire.
4. Choisir un appareil ou **Any iOS Device (arm64)**.
5. Utiliser **Product > Archive**.
6. Dans l’Organizer, choisir **Distribute App** pour exporter l’IPA ou l’envoyer vers TestFlight.

## API nécessaire

L’application utilise `EXPO_PUBLIC_DOMAIN` pour joindre le serveur API. Avant de lancer une version distribuée, le serveur situé dans `artifacts/api-server/` doit être déployé publiquement et cette variable doit pointer vers son domaine.

## Limitation de l’environnement Replit

Le projet natif est prêt, mais la compilation finale en IPA nécessite Xcode et macOS. `xcodebuild` n’est pas disponible sur Linux ; la signature Apple doit donc être faite sur ton Mac avec ton compte Apple Developer.