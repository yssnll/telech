# Téléch — application iOS native Swift

Cette archive contient une version native iOS de l’application Téléch. Elle ne
nécessite ni CocoaPods, ni Swift Package Manager, ni bibliothèque tierce.

## Fonctions conservées

- lecture de liens MP4 et de playlists HLS accessibles directement ;
- détection des liens signés expirés ;
- historique local des cinq derniers liens ;
- téléchargement des MP4 dans le stockage privé de l’application ;
- conversion HLS vers un MP4 compatible iOS pendant le téléchargement ;
- bibliothèque « Hors ligne » persistante, lisible sans Wi-Fi ni réseau ;
- progression, suppression, remplacement d’un téléchargement existant et états
  d’erreur en français ;
- prise en charge des en-têtes nécessaires aux sources déjà gérées par Téléch.

## Compiler avec GitHub Actions

1. Copiez le contenu de cette archive dans un dépôt GitHub.
2. Ouvrez **Actions → Build iOS IPA → Run workflow**.
3. Renseignez `api_domain` avec le domaine public qui expose
   `/api/downloads/mp4` pour convertir les playlists HLS, par exemple
   `https://mon-domaine.example`.
4. Téléchargez l’artefact `telech-unsigned-ipa`.

Le workflow produit une IPA non signée. Apple exige ensuite une signature et un
profil de provisioning pour l’installer sur un iPhone réel. Pour une IPA signée,
ajoutez votre méthode habituelle de signature Apple dans le workflow et utilisez
un Bundle Identifier associé à votre équipe.

## Compilation locale sur macOS

```bash
xcodebuild \
  -project Telech.xcodeproj \
  -scheme Telech \
  -sdk iphoneos \
  -configuration Release \
  -archivePath "$PWD/build/Telech.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  API_BASE_URL="https://mon-domaine.example" \
  archive
```

## Limites techniques

Le premier téléchargement d’une vidéo demande une connexion réseau. Une vidéo
MP4 déjà enregistrée est ensuite entièrement locale. Les flux chiffrés, les
liens expirés, les sources protégées par une page web et les formats que
`AVPlayer` ne sait pas décoder ne peuvent pas être rendus autonomes par l’app.
