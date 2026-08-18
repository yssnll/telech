# Téléchargeur vidéo hors ligne

Application iOS Expo qui lit des fichiers MP4 et des playlists HLS depuis un lien,
puis conserve les vidéos téléchargées dans un onglet Hors ligne sans serveur distant.

## Run & Operate

- `pnpm install` — installer les dépendances
- `pnpm --filter @workspace/hls-video-player run typecheck` — vérifier les sources mobiles
- `pnpm --filter @workspace/hls-video-player run build` — générer les bundles Expo de vérification

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- Expo SDK 54, React Native 0.81 et Expo Router
- `expo-video` pour la lecture native
- `expo-file-system` et AsyncStorage pour la bibliothèque locale

## Where things live

- `artifacts/hls-video-player/app/index.tsx` — onglets Lecture/Hors ligne,
  téléchargement direct et lecture locale
- `artifacts/hls-video-player/app/_layout.tsx` — démarrage Expo autonome
- `artifacts/hls-video-player/IOS_BUILD.md` — instructions de compilation iOS

## Architecture decisions

- L’app mobile ne dépend pas de `artifacts/api-server` pour fonctionner.
- Les MP4 sont stockés dans le dossier privé de l’app.
- Les playlists HLS non chiffrées sont téléchargées segment par segment et
  recréées localement.

## Product

L’utilisateur colle un lien dans Lecture, regarde la vidéo, appuie sur Hors ligne,
puis retrouve et rejoue ses vidéos dans l’onglet Hors ligne sans connexion.

## User preferences

Les textes de l’interface sont en français.

## Gotchas

Les flux HLS chiffrés, les liens expirés et les vidéos protégées par une page web
ne peuvent pas être téléchargés par une app autonome.

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
