import { Feather, Ionicons } from '@expo/vector-icons';
import { Directory, File, Paths } from 'expo-file-system';
import { useVideoPlayer, VideoView } from 'expo-video';
import { LinearGradient } from 'expo-linear-gradient';
import * as Haptics from 'expo-haptics';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  AppState,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { KeyboardAwareScrollViewCompat } from '@/components/KeyboardAwareScrollViewCompat';
import { useColors } from '@/hooks/useColors';
import {
  addNativeHlsCompletedListener,
  addNativeHlsFailedListener,
  addNativeHlsProgressListener,
  deleteNativeHlsDownload,
  isNativeOfflineHlsAvailable,
  startNativeHlsDownload,
} from '@workspace/offline-hls';

const DEFAULT_URL =
  'https://video.sibnet.ru/v/b85c60dd8c85fd25641a21fbcbb3d20c/6223248.m3u8';
const HISTORY_KEY = '@hls-video-player/history';
const OFFLINE_KEY = '@hls-video-player/offline';
const OFFLINE_DIRECTORY = 'offline-videos';
const MAX_HISTORY = 5;

type PlaybackState = 'idle' | 'loading' | 'ready' | 'error';
type DownloadState = 'idle' | 'working';
type Tab = 'playback' | 'offline';

type OfflineVideo = {
  id: string;
  sourceUrl: string;
  localUri: string;
  filename: string;
  createdAt: number;
  size: number;
  // Kept for backwards compatibility with downloads created before the native HLS flow.
  format: 'mp4' | 'hls' | 'native-hls';
};

function isValidStreamUrl(value: string) {
  try {
    const parsed = new URL(value.trim());
    return parsed.protocol === 'https:' || parsed.protocol === 'http:';
  } catch {
    return false;
  }
}

function isHlsUrl(value: string) {
  try {
    return new URL(value).pathname.toLowerCase().endsWith('.m3u8');
  } catch {
    return value.toLowerCase().includes('.m3u8');
  }
}

function shortenUrl(value: string) {
  try {
    const parsed = new URL(value);
    return `${parsed.hostname}${parsed.pathname.length > 24 ? `${parsed.pathname.slice(0, 24)}…` : parsed.pathname}`;
  } catch {
    return value.length > 34 ? `${value.slice(0, 34)}…` : value;
  }
}

function getFilename(streamUrl: string, fallback = 'video') {
  try {
    const pathname = new URL(streamUrl).pathname;
    const lastPart = pathname.split('/').filter(Boolean).pop();
    if (lastPart) {
      const decoded = decodeURIComponent(lastPart).replace(/\.(m3u8|mp4|m4v|mov|ts)$/i, '');
      if (decoded) return decoded.replace(/[^a-zA-Z0-9-_ ]/g, '_').slice(0, 60);
    }
  } catch {
    // Use the fallback when the URL does not contain a usable filename.
  }
  return fallback;
}

function getStreamHeaders(streamUrl: string): Record<string, string> {
  const parsed = new URL(streamUrl);
  const headers: Record<string, string> = {
    Accept: '*/*',
    'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
  };

  if (parsed.hostname === 'video.sibnet.ru' || parsed.hostname.endsWith('.sibnet.ru')) {
    headers.Referer = 'https://video.sibnet.ru/';
    headers.Origin = 'https://video.sibnet.ru';
    headers['Accept-Language'] = 'fr-FR,fr;q=0.9,en;q=0.8';
  }

  if (parsed.hostname === 'uqload.vc' || parsed.hostname.endsWith('.uqload.vc')) {
    headers.Referer = 'https://uqload.to/';
    headers.Origin = 'https://uqload.to';
    headers['Accept-Language'] = 'fr-FR,fr;q=0.9,en;q=0.8';
  }

  return headers;
}

function getSignedUrlExpiry(streamUrl: string): number | null {
  try {
    const params = new URL(streamUrl).searchParams;
    const start = Number(params.get('s'));
    const endOrDuration = Number(params.get('e'));
    if (!Number.isFinite(start) || start <= 0) return null;
    if (Number.isFinite(endOrDuration) && endOrDuration > 0) {
      const end = endOrDuration >= 1_000_000_000 ? endOrDuration : start + endOrDuration;
      return end * 1000;
    }
    return null;
  } catch {
    return null;
  }
}

function formatExpiry(expiry: number) {
  return new Intl.DateTimeFormat('fr-BE', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(expiry));
}

function formatBytes(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} Ko`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} Go`;
}

function formatDate(timestamp: number) {
  return new Intl.DateTimeFormat('fr-BE', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(timestamp));
}

function createOfflineId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

function isLocalUri(value: string) {
  return value.startsWith('file://') || value.startsWith('/');
}

export default function PlayerScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const [activeTab, setActiveTab] = useState<Tab>('playback');
  const [url, setUrl] = useState<string>(DEFAULT_URL);
  const [activeUrl, setActiveUrl] = useState<string | null>(null);
  const [activeTitle, setActiveTitle] = useState<string | null>(null);
  const [history, setHistory] = useState<string[]>([]);
  const [offlineVideos, setOfflineVideos] = useState<OfflineVideo[]>([]);
  const [state, setState] = useState<PlaybackState>('idle');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [downloadState, setDownloadState] = useState<DownloadState>('idle');
  const [downloadMessage, setDownloadMessage] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState<number | null>(null);
  const activeUrlRef = useRef<string | null>(null);

  activeUrlRef.current = activeUrl;

  const player = useVideoPlayer(null, (videoPlayer) => {
    videoPlayer.loop = false;
    videoPlayer.audioMixingMode = 'doNotMix';
    videoPlayer.keepScreenOnWhilePlaying = true;
  });

  useEffect(() => {
    let isMounted = true;
    Promise.all([AsyncStorage.getItem(HISTORY_KEY), AsyncStorage.getItem(OFFLINE_KEY)])
      .then(([storedHistory, storedOffline]) => {
        if (!isMounted) return;
        if (storedHistory) {
          const parsed: unknown = JSON.parse(storedHistory);
          if (Array.isArray(parsed)) {
            setHistory(parsed.filter((item): item is string => typeof item === 'string').slice(0, MAX_HISTORY));
          }
        }
        if (storedOffline) {
          const parsed: unknown = JSON.parse(storedOffline);
          if (Array.isArray(parsed)) {
            setOfflineVideos(
              parsed.filter(
                (item): item is OfflineVideo =>
                  Boolean(
                    item &&
                      typeof item === 'object' &&
                      typeof (item as OfflineVideo).id === 'string' &&
                      typeof (item as OfflineVideo).localUri === 'string' &&
                      typeof (item as OfflineVideo).filename === 'string',
                  ),
              ),
            );
          }
        }
      })
      .catch(() => undefined);

    const subscription = player.addListener('statusChange', ({ status, error }) => {
      if (!isMounted) return;
      if (status === 'loading') setState('loading');
      if (status === 'readyToPlay') {
        setState('ready');
        setErrorMessage(null);
      }
      if (status === 'error') {
        setState('error');
        setErrorMessage(error?.message ?? 'Impossible de charger cette vidéo.');
      }
    });

    return () => {
      isMounted = false;
      subscription.remove();
    };
  }, [player]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'background' && downloadState === 'working' && Platform.OS !== 'web') {
        setDownloadMessage('Téléchargement en arrière-plan géré par iOS. Vous pouvez quitter cet écran.');
      }
    });
    return () => subscription.remove();
  }, [downloadState]);

  const sourceLabel = useMemo(
    () => activeTitle ?? (activeUrl ? shortenUrl(activeUrl) : 'Aucune vidéo active'),
    [activeTitle, activeUrl],
  );

  const persistHistory = async (nextHistory: string[]) => {
    setHistory(nextHistory);
    await AsyncStorage.setItem(HISTORY_KEY, JSON.stringify(nextHistory));
  };

  const persistOfflineVideos = async (nextVideos: OfflineVideo[]) => {
    setOfflineVideos(nextVideos);
    await AsyncStorage.setItem(OFFLINE_KEY, JSON.stringify(nextVideos));
  };

  const loadVideo = async (sourceUrl: string, title?: string) => {
    setState('loading');
    setErrorMessage(null);
    setActiveUrl(sourceUrl);
    setActiveTitle(title ?? null);
    activeUrlRef.current = sourceUrl;

    try {
      await player.replaceAsync({
        uri: sourceUrl,
        ...(isHlsUrl(sourceUrl) ? { contentType: 'hls' as const } : {}),
        ...(isLocalUri(sourceUrl) ? {} : { headers: getStreamHeaders(sourceUrl) }),
        metadata: {
          title: title ?? 'Vidéo hors ligne',
          artist: 'Lecteur vidéo',
        },
      });
      player.play();
    } catch (error) {
      setState('error');
      setErrorMessage(error instanceof Error ? error.message : 'Impossible de charger cette vidéo.');
    }
  };

  const openStream = async (candidate = url) => {
    const nextUrl = candidate.trim();
    if (!isValidStreamUrl(nextUrl)) {
      setState('error');
      setErrorMessage('Collez une adresse vidéo complète commençant par http:// ou https://.');
      return;
    }

    const signedUrlExpiry = getSignedUrlExpiry(nextUrl);
    if (signedUrlExpiry && signedUrlExpiry <= Date.now()) {
      setUrl(nextUrl);
      setActiveUrl(nextUrl);
      setActiveTitle(null);
      setState('error');
      setErrorMessage(`Ce lien signé a expiré le ${formatExpiry(signedUrlExpiry)}. Demandez un nouveau lien au site source.`);
      return;
    }

    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setUrl(nextUrl);
    setShowDetails(false);
    const nextHistory = [nextUrl, ...history.filter((item) => item !== nextUrl)].slice(0, MAX_HISTORY);
    await persistHistory(nextHistory);
    await loadVideo(nextUrl);
  };

  const clearHistory = async () => {
    await Haptics.selectionAsync();
    await persistHistory([]);
  };

  const downloadDirectVideo = async (sourceUrl: string, destination: File) => {
    const result = await File.downloadFileAsync(sourceUrl, destination, { idempotent: true });
    if (!result.exists || result.size <= 0) {
      throw new Error('Le fichier vidéo reçu est vide ou indisponible.');
    }
    return result;
  };

  const downloadHlsNatively = async (
    sourceUrl: string,
    id: string,
    title: string,
    onProgress: (value: number) => void,
  ) => {
    if (!isNativeOfflineHlsAvailable()) {
      throw new Error(
        'Cette fonction nécessite la build iOS autonome. Expo Go et l’aperçu web ne peuvent pas lancer un téléchargement HLS en arrière-plan.',
      );
    }

    onProgress(1);
    return new Promise<{ localUri: string; size: number }>((resolve, reject) => {
      const completedSubscription = addNativeHlsCompletedListener((event) => {
        if (event.id !== id) return;
        completedSubscription.remove();
        failedSubscription.remove();
        progressSubscription.remove();
        onProgress(100);
        resolve({ localUri: event.localUri, size: event.size });
      });
      const failedSubscription = addNativeHlsFailedListener((event) => {
        if (event.id !== id) return;
        completedSubscription.remove();
        failedSubscription.remove();
        progressSubscription.remove();
        reject(new Error(event.message));
      });
      const progressSubscription = addNativeHlsProgressListener((event) => {
        if (event.id === id) onProgress(Math.round(event.progress * 100));
      });

      void startNativeHlsDownload(sourceUrl, id, title, getStreamHeaders(sourceUrl)).catch((error) => {
        progressSubscription.remove();
        completedSubscription.remove();
        failedSubscription.remove();
        reject(error instanceof Error ? error : new Error('Le téléchargement HLS a échoué.'));
      });
    });
  };

  const downloadSource = async (requestedSourceUrl?: string) => {
    const sourceUrl = (requestedSourceUrl ?? activeUrl ?? url).trim();
    if (!isValidStreamUrl(sourceUrl)) {
      setState('error');
      setErrorMessage('Collez une adresse vidéo valide avant de télécharger.');
      return;
    }
    if (Platform.OS === 'web') {
      setState('error');
      setErrorMessage('Le stockage hors ligne est disponible dans l’application iOS, pas dans l’aperçu web.');
      return;
    }

    const id = createOfflineId();
    const filename = `${getFilename(sourceUrl)}${isHlsUrl(sourceUrl) ? '' : '.mp4'}`;
    const directory = new Directory(Paths.document, OFFLINE_DIRECTORY, id);
    setDownloadState('working');
    setDownloadProgress(0);
    setDownloadMessage(isHlsUrl(sourceUrl) ? 'Téléchargement HLS natif…' : 'Téléchargement de la vidéo…');

    try {
      let localUri: string;
      let size: number;
      let format: OfflineVideo['format'];

      if (isHlsUrl(sourceUrl)) {
        setDownloadMessage('Téléchargement HLS natif…');
        const result = await downloadHlsNatively(
          sourceUrl,
          id,
          getFilename(sourceUrl),
          setDownloadProgress,
        );
        localUri = result.localUri;
        size = result.size;
        format = 'native-hls';
      } else {
        directory.create({ idempotent: true, intermediates: true });
        const result = await downloadDirectVideo(sourceUrl, new File(directory, 'video.mp4'));
        localUri = result.uri;
        size = result.size;
        setDownloadProgress(100);
        format = 'mp4';
      }

      const item: OfflineVideo = {
        id,
        sourceUrl,
        localUri,
        filename,
        createdAt: Date.now(),
        size,
        format,
      };
      const previousVideo = offlineVideos.find((video) => video.sourceUrl === sourceUrl);
      await persistOfflineVideos([item, ...offlineVideos.filter((video) => video.sourceUrl !== sourceUrl)]);
      if (previousVideo && previousVideo.id !== id) {
        if (previousVideo.format === 'native-hls') {
          await deleteNativeHlsDownload(previousVideo.id);
        } else {
          new Directory(Paths.document, OFFLINE_DIRECTORY, previousVideo.id).delete();
        }
      }
      setDownloadMessage('Vidéo enregistrée. Elle est maintenant disponible dans Hors ligne.');
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch (error) {
      if (!isHlsUrl(sourceUrl)) {
        new Directory(Paths.document, OFFLINE_DIRECTORY, id).delete();
      }
      const message = error instanceof Error ? error.message : 'Le téléchargement a échoué.';
      setDownloadMessage(`Téléchargement impossible : ${message}`);
      Alert.alert('Téléchargement impossible', message);
    } finally {
      setDownloadState('idle');
    }
  };

  const playOfflineVideo = async (video: OfflineVideo) => {
    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    const isLegacyHls = video.format === 'hls' || video.localUri.toLowerCase().endsWith('.m3u8');
    if (isLegacyHls) {
      Alert.alert(
        'Ancien téléchargement HLS',
        'Cette vidéo a été enregistrée dans un ancien format qui n’est pas fiable sur iOS. Téléchargez-la à nouveau pour utiliser le téléchargement HLS natif.',
        [
          { text: 'Plus tard', style: 'cancel' },
          {
            text: 'Retélécharger en natif',
            onPress: () => {
              setActiveTab('playback');
              setUrl(video.sourceUrl);
              setActiveUrl(video.sourceUrl);
              setActiveTitle(null);
              void downloadSource(video.sourceUrl);
            },
          },
        ],
      );
      return;
    }
    setActiveTab('playback');
    setDownloadMessage(null);
    await loadVideo(video.localUri, video.filename);
  };

  const removeOfflineVideo = (video: OfflineVideo) => {
    Alert.alert('Supprimer la vidéo ?', `${video.filename} sera retirée de l’onglet Hors ligne.`, [
      { text: 'Annuler', style: 'cancel' },
      {
        text: 'Supprimer',
        style: 'destructive',
        onPress: () => {
          void (async () => {
            if (video.format === 'native-hls') {
              await deleteNativeHlsDownload(video.id);
            } else {
              new Directory(Paths.document, OFFLINE_DIRECTORY, video.id).delete();
            }
            await persistOfflineVideos(offlineVideos.filter((item) => item.id !== video.id));
          })();
        },
      },
    ]);
  };

  const stateCopy = {
    idle: { label: 'Prêt à lire', color: colors.mutedForeground },
    loading: { label: 'Chargement…', color: colors.warning },
    ready: { label: 'Lecture en cours', color: colors.success },
    error: { label: 'Vidéo indisponible', color: colors.destructive },
  }[state];
  const signedUrlExpiry = activeUrl && !isLocalUri(activeUrl) ? getSignedUrlExpiry(activeUrl) : null;
  const errorTitle = signedUrlExpiry && signedUrlExpiry <= Date.now()
    ? 'Le lien a expiré'
    : errorMessage?.includes('403')
      ? 'Accès refusé par le site source'
      : 'Lecture refusée';

  const renderHeader = () => (
    <>
      <View style={styles.header}>
        <View style={styles.brandMark}>
          <Ionicons name="play" size={20} color={colors.primaryForeground} />
        </View>
        <View style={styles.headerText}>
          <Text style={[styles.eyebrow, { color: colors.accent }]}>LECTEUR VIDÉO</Text>
          <Text style={[styles.title, { color: colors.foreground }]}>Regarder, puis garder.</Text>
        </View>
        <View style={[styles.offlinePill, { backgroundColor: colors.secondary }]}>
          <Ionicons name="shield-checkmark-outline" size={13} color={colors.accent} />
          <Text style={[styles.liveText, { color: colors.secondaryForeground }]}>local</Text>
        </View>
      </View>

      <View style={[styles.tabs, { backgroundColor: colors.card, borderColor: colors.border }]}>
        <Pressable
          testID="playback-tab"
          onPress={() => setActiveTab('playback')}
          style={[styles.tab, activeTab === 'playback' && { backgroundColor: colors.primary }]}
        >
          <Ionicons
            name="play-circle-outline"
            size={18}
            color={activeTab === 'playback' ? colors.primaryForeground : colors.mutedForeground}
          />
          <Text style={[styles.tabText, { color: activeTab === 'playback' ? colors.primaryForeground : colors.mutedForeground }]}>
            Lecture
          </Text>
        </Pressable>
        <Pressable
          testID="offline-tab"
          onPress={() => setActiveTab('offline')}
          style={[styles.tab, activeTab === 'offline' && { backgroundColor: colors.primary }]}
        >
          <Ionicons
            name="download-outline"
            size={18}
            color={activeTab === 'offline' ? colors.primaryForeground : colors.mutedForeground}
          />
          <Text style={[styles.tabText, { color: activeTab === 'offline' ? colors.primaryForeground : colors.mutedForeground }]}>
            Hors ligne
          </Text>
          {offlineVideos.length > 0 ? (
            <View style={[styles.countBadge, { backgroundColor: activeTab === 'offline' ? colors.primaryForeground : colors.secondary }]}>
              <Text style={[styles.countText, { color: activeTab === 'offline' ? colors.primary : colors.foreground }]}>
                {offlineVideos.length}
              </Text>
            </View>
          ) : null}
        </Pressable>
      </View>
    </>
  );

  const renderPlayer = () => (
    <>
      <Text style={[styles.subtitle, { color: colors.mutedForeground }]}>
        Collez le lien d’une vidéo ou d’une playlist .m3u8, regardez-la, puis gardez-la sur l’iPhone.
      </Text>

      <View style={[styles.playerShell, { borderColor: colors.border, backgroundColor: colors.card }]}>
        {activeUrl ? (
          <VideoView
            player={player}
            style={styles.video}
            nativeControls
            contentFit="contain"
            allowsFullscreen
            allowsPictureInPicture
          />
        ) : (
          <View style={styles.emptyPlayer}>
            <View style={[styles.emptyIcon, { backgroundColor: colors.secondary }]}>
              <Ionicons name="play-outline" size={34} color={colors.primary} />
            </View>
            <Text style={[styles.emptyTitle, { color: colors.foreground }]}>Votre vidéo apparaîtra ici</Text>
            <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
              La lecture et l’enregistrement se font depuis cet écran.
            </Text>
          </View>
        )}
        {activeUrl && state === 'loading' ? (
          <View style={[styles.loadingBadge, { backgroundColor: colors.overlay }]}>
            <Text style={[styles.loadingBadgeText, { color: colors.warning }]}>CHARGEMENT</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.statusRow}>
        <View style={[styles.statusDot, { backgroundColor: stateCopy.color }]} />
        <Text style={[styles.statusText, { color: colors.mutedForeground }]}>{stateCopy.label}</Text>
        {activeUrl ? (
          <Text numberOfLines={1} style={[styles.activeLabel, { color: colors.foreground }]}>
            {sourceLabel}
          </Text>
        ) : null}
      </View>

      <View style={[styles.formCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
        <View style={styles.fieldHeader}>
          <Text style={[styles.fieldLabel, { color: colors.foreground }]}>Adresse de la vidéo</Text>
          <Text style={[styles.fieldHint, { color: colors.mutedForeground }]}>MP4 / HLS</Text>
        </View>
        <View style={[styles.inputWrap, { backgroundColor: colors.input, borderColor: colors.border }]}>
          <Ionicons name="link-outline" size={18} color={colors.mutedForeground} />
          <TextInput
            testID="stream-url-input"
            value={url}
            onChangeText={setUrl}
            placeholder="https://…/video.m3u8"
            placeholderTextColor={colors.mutedForeground}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
            returnKeyType="go"
            onSubmitEditing={() => void openStream()}
            style={[styles.input, { color: colors.foreground }]}
          />
          {url.length > 0 ? (
            <Pressable
              accessibilityLabel="Effacer l’adresse"
              hitSlop={12}
              onPress={() => setUrl('')}
              style={({ pressed }) => [{ opacity: pressed ? 0.5 : 1 }]}
            >
              <Ionicons name="close-circle" size={18} color={colors.mutedForeground} />
            </Pressable>
          ) : null}
        </View>
        <View style={styles.actionRow}>
          <Pressable
            testID="open-stream-button"
            onPress={() => void openStream()}
            style={({ pressed }) => [
              styles.openButton,
              styles.playButton,
              { backgroundColor: colors.primary, opacity: pressed ? 0.78 : 1 },
            ]}
          >
            <Ionicons name="play" size={18} color={colors.primaryForeground} />
            <Text style={[styles.openButtonText, { color: colors.primaryForeground }]}>Lire</Text>
            <Feather name="arrow-up-right" size={17} color={colors.primaryForeground} />
          </Pressable>
          <Pressable
            testID="download-button"
            accessibilityLabel="Télécharger la vidéo pour la regarder hors ligne"
            disabled={downloadState === 'working' || isLocalUri(activeUrl ?? '')}
            onPress={() => void downloadSource()}
            style={({ pressed }) => [
              styles.openButton,
              styles.downloadButton,
              {
                backgroundColor: colors.secondary,
                borderColor: colors.border,
                opacity: pressed || downloadState === 'working' ? 0.55 : 1,
              },
            ]}
          >
            <Ionicons name="download-outline" size={19} color={colors.secondaryForeground} />
            <Text style={[styles.downloadButtonText, { color: colors.secondaryForeground }]}>
              {downloadState === 'working' ? 'Téléchargement…' : 'Hors ligne'}
            </Text>
          </Pressable>
        </View>
      </View>

      {downloadMessage ? (
        <View style={[styles.downloadStatusCard, { backgroundColor: colors.secondary, borderColor: colors.border }]}>
          <Ionicons name={downloadState === 'working' ? 'sync-outline' : 'checkmark-circle-outline'} size={18} color={colors.accent} />
          <View style={styles.downloadStatusCopy}>
            <Text style={[styles.downloadStatusText, { color: colors.secondaryForeground }]}>{downloadMessage}</Text>
            {downloadState === 'working' ? (
              <View style={[styles.progressTrack, { backgroundColor: colors.input }]}>
                <View style={[styles.progressFill, { backgroundColor: colors.accent, width: `${downloadProgress ?? 4}%` }]} />
              </View>
            ) : null}
            {downloadState === 'working' && downloadProgress !== null ? (
              <Text style={[styles.progressBytes, { color: colors.mutedForeground }]}>{downloadProgress}%</Text>
            ) : null}
          </View>
        </View>
      ) : null}

      {state === 'error' && errorMessage ? (
        <View style={[styles.errorCard, { backgroundColor: colors.card, borderColor: colors.destructive }]}>
          <View style={[styles.errorIcon, { backgroundColor: `${colors.destructive}20` }]}>
            <Ionicons name="shield-outline" size={21} color={colors.destructive} />
          </View>
          <View style={styles.errorCopy}>
            <Text style={[styles.errorTitle, { color: colors.foreground }]}>{errorTitle}</Text>
            <Text style={[styles.errorText, { color: colors.mutedForeground }]}>
              {errorMessage}{' '}
              {signedUrlExpiry && signedUrlExpiry <= Date.now()
                ? 'Collez un nouveau lien généré par le site source.'
                : 'Le lecteur autonome ne passe pas par un relais serveur : le site source doit autoriser l’accès direct.'}
            </Text>
            <Pressable
              onPress={() => setShowDetails((value) => !value)}
              style={({ pressed }) => [{ opacity: pressed ? 0.6 : 1 }]}
            >
              <Text style={[styles.detailsLink, { color: colors.accent }]}>
                {showDetails ? 'Masquer le diagnostic' : 'Voir le diagnostic'}
              </Text>
            </Pressable>
            {showDetails ? (
              <Text style={[styles.detailsText, { color: colors.mutedForeground }]}>
                Les vidéos protégées, chiffrées ou limitées à une page web ne peuvent pas être récupérées par une app autonome.
              </Text>
            ) : null}
          </View>
        </View>
      ) : null}

      {history.length > 0 ? (
        <View style={styles.historySection}>
          <View style={styles.sectionHeader}>
            <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Récents</Text>
            <Pressable onPress={() => void clearHistory()} style={({ pressed }) => [{ opacity: pressed ? 0.5 : 1 }]}>
              <Text style={[styles.clearText, { color: colors.mutedForeground }]}>Effacer</Text>
            </Pressable>
          </View>
          {history.map((item) => (
            <Pressable
              key={item}
              testID={`recent-stream-${item}`}
              onPress={() => void openStream(item)}
              style={({ pressed }) => [
                styles.historyRow,
                { backgroundColor: colors.card, borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <View style={[styles.historyIcon, { backgroundColor: colors.secondary }]}>
                <Ionicons name="play-circle-outline" size={20} color={colors.accent} />
              </View>
              <Text numberOfLines={1} style={[styles.historyText, { color: colors.foreground }]}>
                {shortenUrl(item)}
              </Text>
              <Feather name="chevron-right" size={18} color={colors.mutedForeground} />
            </Pressable>
          ))}
        </View>
      ) : null}
    </>
  );

  const renderOffline = () => (
    <View style={styles.offlineContent}>
      <View style={styles.offlineIntro}>
        <View style={[styles.offlineIntroIcon, { backgroundColor: colors.secondary }]}>
          <Ionicons name="cloud-offline-outline" size={28} color={colors.accent} />
        </View>
        <Text style={[styles.offlineTitle, { color: colors.foreground }]}>Vos vidéos, même sans réseau.</Text>
        <Text style={[styles.offlineSubtitle, { color: colors.mutedForeground }]}>
          Les vidéos téléchargées restent dans le stockage privé de cette app.
        </Text>
      </View>

      {offlineVideos.length === 0 ? (
        <View style={[styles.emptyOffline, { backgroundColor: colors.card, borderColor: colors.border }]}>
          <Ionicons name="download-outline" size={28} color={colors.mutedForeground} />
          <Text style={[styles.emptyOfflineTitle, { color: colors.foreground }]}>Aucune vidéo hors ligne</Text>
          <Text style={[styles.emptyOfflineText, { color: colors.mutedForeground }]}>
            Ouvrez l’onglet Lecture, collez un lien, puis appuyez sur Hors ligne.
          </Text>
          <Pressable
            onPress={() => setActiveTab('playback')}
            style={({ pressed }) => [styles.emptyOfflineButton, { backgroundColor: colors.primary, opacity: pressed ? 0.78 : 1 }]}
          >
            <Ionicons name="play" size={16} color={colors.primaryForeground} />
            <Text style={[styles.emptyOfflineButtonText, { color: colors.primaryForeground }]}>Ajouter une vidéo</Text>
          </Pressable>
        </View>
      ) : (
        <View style={styles.offlineList}>
          <View style={styles.sectionHeader}>
            <Text style={[styles.sectionTitle, { color: colors.foreground }]}>{offlineVideos.length} vidéo{offlineVideos.length > 1 ? 's' : ''}</Text>
            <Text style={[styles.clearText, { color: colors.mutedForeground }]}>Stockage privé</Text>
          </View>
          {offlineVideos.map((video) => (
            <View key={video.id} style={[styles.offlineRow, { backgroundColor: colors.card, borderColor: colors.border }]}>
              <Pressable
                testID={`offline-video-${video.id}`}
                onPress={() => void playOfflineVideo(video)}
                style={({ pressed }) => [styles.offlineRowMain, { opacity: pressed ? 0.72 : 1 }]}
              >
                <View style={[styles.offlineThumbnail, { backgroundColor: colors.secondary }]}>
                  <Ionicons name="play" size={22} color={colors.accent} />
                </View>
                <View style={styles.offlineCopy}>
                  <Text numberOfLines={1} style={[styles.offlineFilename, { color: colors.foreground }]}>{video.filename}</Text>
                  <Text style={[styles.offlineMeta, { color: colors.mutedForeground }]}>
                    {formatBytes(video.size)} · {formatDate(video.createdAt)}
                  </Text>
                  <Text style={[styles.offlineFormat, { color: colors.accent }]}>
                    {video.format === 'native-hls'
                      ? 'Téléchargement HLS natif iOS'
                      : video.format === 'hls'
                        ? 'Playlist HLS locale'
                        : 'Fichier vidéo local'}
                  </Text>
                </View>
                <Feather name="play-circle" size={22} color={colors.primary} />
              </Pressable>
              <Pressable
                testID={`delete-offline-video-${video.id}`}
                accessibilityLabel={`Supprimer ${video.filename}`}
                hitSlop={10}
                onPress={() => removeOfflineVideo(video)}
                style={({ pressed }) => [styles.deleteOfflineButton, { opacity: pressed ? 0.5 : 1 }]}
              >
                <Ionicons name="trash-outline" size={18} color={colors.destructive} />
              </Pressable>
            </View>
          ))}
        </View>
      )}
    </View>
  );

  return (
    <View style={[styles.screen, { backgroundColor: colors.background }]}>
      <LinearGradient colors={[colors.overlay, colors.background, colors.background]} style={StyleSheet.absoluteFill} />
      <KeyboardAwareScrollViewCompat
        style={styles.scroll}
        contentContainerStyle={{ paddingTop: insets.top + 20, paddingBottom: insets.bottom + 30 }}
        bottomOffset={24}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {renderHeader()}
        {activeTab === 'playback' ? renderPlayer() : <ScrollView scrollEnabled={false}>{renderOffline()}</ScrollView>}
        <View style={styles.footer}>
          <Ionicons name="lock-closed-outline" size={13} color={colors.mutedForeground} />
          <Text style={[styles.footerText, { color: colors.mutedForeground }]}>
            Vidéos conservées uniquement sur cet appareil
          </Text>
        </View>
      </KeyboardAwareScrollViewCompat>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  scroll: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 22 },
  brandMark: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#ff725c',
    transform: [{ rotate: '-8deg' }],
  },
  headerText: { flex: 1, marginLeft: 14 },
  eyebrow: { fontSize: 11, fontFamily: 'Inter_700Bold', letterSpacing: 1.4 },
  title: { fontSize: 25, lineHeight: 31, fontFamily: 'Inter_700Bold', letterSpacing: -0.8 },
  offlinePill: { flexDirection: 'row', alignItems: 'center', borderRadius: 999, paddingHorizontal: 10, paddingVertical: 7, gap: 5 },
  liveText: { fontSize: 11, fontFamily: 'Inter_600SemiBold' },
  tabs: { flexDirection: 'row', borderWidth: 1, borderRadius: 17, marginHorizontal: 18, marginTop: 22, padding: 4 },
  tab: { flex: 1, minHeight: 44, borderRadius: 13, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7 },
  tabText: { fontSize: 13, fontFamily: 'Inter_700Bold' },
  countBadge: { minWidth: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 5 },
  countText: { fontSize: 10, fontFamily: 'Inter_700Bold' },
  subtitle: { fontSize: 14, lineHeight: 21, marginTop: 16, marginBottom: 20, paddingHorizontal: 22 },
  playerShell: { marginHorizontal: 18, borderWidth: 1, borderRadius: 24, overflow: 'hidden', aspectRatio: 16 / 10 },
  video: { flex: 1, backgroundColor: '#080a12' },
  emptyPlayer: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 30 },
  emptyIcon: { width: 70, height: 70, borderRadius: 24, alignItems: 'center', justifyContent: 'center', marginBottom: 16 },
  emptyTitle: { fontSize: 16, fontFamily: 'Inter_600SemiBold', textAlign: 'center' },
  emptyText: { fontSize: 13, lineHeight: 19, textAlign: 'center', marginTop: 8 },
  loadingBadge: { position: 'absolute', top: 12, left: 12, borderRadius: 999, paddingHorizontal: 9, paddingVertical: 6 },
  loadingBadgeText: { fontSize: 10, fontFamily: 'Inter_700Bold', letterSpacing: 1 },
  statusRow: { flexDirection: 'row', alignItems: 'center', marginHorizontal: 24, marginTop: 12, minHeight: 22 },
  statusDot: { width: 7, height: 7, borderRadius: 4, marginRight: 7 },
  statusText: { fontSize: 12, fontFamily: 'Inter_500Medium' },
  activeLabel: { flex: 1, fontSize: 12, textAlign: 'right', marginLeft: 12, fontFamily: 'Inter_500Medium' },
  formCard: { margin: 18, marginTop: 15, borderWidth: 1, borderRadius: 22, padding: 16 },
  fieldHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 },
  fieldLabel: { fontSize: 14, fontFamily: 'Inter_600SemiBold' },
  fieldHint: { fontSize: 10, fontFamily: 'Inter_700Bold', letterSpacing: 1 },
  inputWrap: { minHeight: 52, borderRadius: 15, borderWidth: 1, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14 },
  input: { flex: 1, fontSize: 13, fontFamily: 'Inter_400Regular', paddingHorizontal: 10, paddingVertical: 12 },
  openButton: { minHeight: 52, borderRadius: 15, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginTop: 12, gap: 9 },
  actionRow: { flexDirection: 'row', gap: 9 },
  playButton: { flex: 1 },
  downloadButton: { paddingHorizontal: 14, borderWidth: 1, gap: 7 },
  openButtonText: { fontSize: 15, fontFamily: 'Inter_700Bold' },
  downloadButtonText: { fontSize: 13, fontFamily: 'Inter_700Bold' },
  downloadStatusCard: { marginHorizontal: 18, marginTop: 12, borderRadius: 16, borderWidth: 1, flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 13, paddingVertical: 11, gap: 8 },
  downloadStatusCopy: { flex: 1 },
  downloadStatusText: { flex: 1, fontSize: 12, lineHeight: 17, fontFamily: 'Inter_500Medium' },
  progressTrack: { height: 7, borderRadius: 999, overflow: 'hidden', marginTop: 9 },
  progressFill: { height: '100%', borderRadius: 999 },
  progressBytes: { fontSize: 10, marginTop: 5, fontFamily: 'Inter_400Regular' },
  errorCard: { marginHorizontal: 18, borderWidth: 1, borderRadius: 20, padding: 15, flexDirection: 'row' },
  errorIcon: { width: 38, height: 38, borderRadius: 13, alignItems: 'center', justifyContent: 'center', marginRight: 11 },
  errorCopy: { flex: 1 },
  errorTitle: { fontSize: 14, fontFamily: 'Inter_700Bold' },
  errorText: { fontSize: 12, lineHeight: 18, marginTop: 5 },
  detailsLink: { fontSize: 12, fontFamily: 'Inter_600SemiBold', marginTop: 8 },
  detailsText: { fontSize: 12, lineHeight: 18, marginTop: 7 },
  historySection: { marginHorizontal: 18, marginTop: 26 },
  sectionHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10, paddingHorizontal: 4 },
  sectionTitle: { fontSize: 16, fontFamily: 'Inter_700Bold' },
  clearText: { fontSize: 12, fontFamily: 'Inter_500Medium' },
  historyRow: { flexDirection: 'row', alignItems: 'center', minHeight: 58, borderWidth: 1, borderRadius: 17, paddingHorizontal: 11, marginBottom: 8 },
  historyIcon: { width: 34, height: 34, borderRadius: 11, alignItems: 'center', justifyContent: 'center', marginRight: 10 },
  historyText: { flex: 1, fontSize: 12, fontFamily: 'Inter_500Medium' },
  offlineContent: { paddingHorizontal: 18, paddingTop: 24 },
  offlineIntro: { alignItems: 'center', paddingHorizontal: 20, marginBottom: 24 },
  offlineIntroIcon: { width: 62, height: 62, borderRadius: 22, alignItems: 'center', justifyContent: 'center', marginBottom: 13 },
  offlineTitle: { fontSize: 20, textAlign: 'center', fontFamily: 'Inter_700Bold', letterSpacing: -0.4 },
  offlineSubtitle: { fontSize: 13, lineHeight: 19, textAlign: 'center', marginTop: 7 },
  emptyOffline: { borderWidth: 1, borderRadius: 22, alignItems: 'center', paddingHorizontal: 24, paddingVertical: 34 },
  emptyOfflineTitle: { fontSize: 16, fontFamily: 'Inter_700Bold', marginTop: 12 },
  emptyOfflineText: { fontSize: 13, lineHeight: 19, textAlign: 'center', marginTop: 7 },
  emptyOfflineButton: { minHeight: 46, borderRadius: 14, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, gap: 8, marginTop: 18 },
  emptyOfflineButtonText: { fontSize: 13, fontFamily: 'Inter_700Bold' },
  offlineList: { marginBottom: 4 },
  offlineRow: { borderWidth: 1, borderRadius: 18, flexDirection: 'row', alignItems: 'center', padding: 10, marginBottom: 9 },
  offlineRowMain: { flex: 1, flexDirection: 'row', alignItems: 'center' },
  offlineThumbnail: { width: 58, height: 58, borderRadius: 16, alignItems: 'center', justifyContent: 'center', marginRight: 11 },
  offlineCopy: { flex: 1, paddingRight: 8 },
  offlineFilename: { fontSize: 13, fontFamily: 'Inter_700Bold' },
  offlineMeta: { fontSize: 10, marginTop: 5, fontFamily: 'Inter_400Regular' },
  offlineFormat: { fontSize: 10, marginTop: 4, fontFamily: 'Inter_600SemiBold' },
  deleteOfflineButton: { width: 34, height: 42, alignItems: 'center', justifyContent: 'center' },
  footer: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginTop: 28, gap: 5 },
  footerText: { fontSize: 11, fontFamily: 'Inter_400Regular' },
});