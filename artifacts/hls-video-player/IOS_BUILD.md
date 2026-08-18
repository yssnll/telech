# Construire l’application iOS

Le dossier `ios/` a été généré à partir de la configuration Expo du projet. Il contient le projet Xcode et le fichier Swift de démarrage de l’application.

## IPA non signée via GitHub Actions

Le workflow `.github/workflows/build-ios-unsigned.yml` se lance depuis l’onglet
**Actions** de GitHub avec **Run workflow**, ou automatiquement lorsqu’un tag
commençant par `v` est poussé.

Lors d’un lancement manuel, renseignez l’URL publique de l’application
Replit dans le champ `api_domain` (par exemple `https://mon-app.replit.app`).
Cette adresse doit être celle de l’application publiée qui expose l’API sous
`/api`. Pour les builds par tag, configurez plutôt la variable GitHub Actions
`EXPO_PUBLIC_DOMAIN`.

Il :

1. installe les dépendances JavaScript ;
2. régénère le projet iOS avec Expo ;
3. installe les dépendances CocoaPods ;
4. archive l’application avec `CODE_SIGNING_ALLOWED=NO` ;
5. crée `HLSVideoPlayer-unsigned.ipa` et le publie comme artefact GitHub.

### Limitation importante

Une IPA non signée **ne peut pas être installée directement sur un iPhone**.
Apple exige une signature et un profil de provisioning pour toute installation
sur appareil réel. L’artefact généré est donc destiné à être signé ensuite avec
un certificat Apple, un profil de provisioning et un identifiant d’application
autorisés.

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

## Fonctionnement autonome

L’application mobile n’utilise plus le serveur API pour lire ou télécharger une vidéo.
Les fichiers MP4 sont téléchargés directement dans le stockage privé de l’app. Pour
une playlist HLS non chiffrée, l’app télécharge les segments et crée une playlist
`.m3u8` locale. Les vidéos apparaissent ensuite dans l’onglet **Hors ligne**.

Les flux chiffrés, les liens expirés et les vidéos accessibles uniquement derrière
une page web ne peuvent pas être récupérés par une application autonome.

## Limitation de l’environnement Replit

Le projet natif est prêt, mais la compilation finale en IPA nécessite Xcode et macOS. `xcodebuild` n’est pas disponible sur Linux ; la signature Apple doit donc être faite sur ton Mac avec ton compte Apple Developer.