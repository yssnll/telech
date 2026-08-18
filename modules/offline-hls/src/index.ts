import { Platform } from 'react-native';
import { requireOptionalNativeModule } from 'expo-modules-core';

export type OfflineHlsProgressEvent = {
  id: string;
  progress: number;
};

export type OfflineHlsCompletedEvent = {
  id: string;
  localUri: string;
  size: number;
};

export type OfflineHlsFailedEvent = {
  id: string;
  message: string;
};

type NativeSubscription = {
  remove: () => void;
};

type OfflineHlsNativeModule = {
  startDownload: (
    url: string,
    id: string,
    title: string,
    headers: Record<string, string>,
  ) => Promise<{ id: string }>;
  cancelDownload: (id: string) => Promise<void>;
  deleteDownload: (id: string) => Promise<void>;
  addListener: (
    eventName: string,
    listener: (event: unknown) => void,
  ) => NativeSubscription;
};

const nativeModule =
  Platform.OS === 'ios'
    ? requireOptionalNativeModule<OfflineHlsNativeModule>('OfflineHls')
    : null;

export function isNativeOfflineHlsAvailable() {
  return nativeModule !== null;
}

export async function startNativeHlsDownload(
  url: string,
  id: string,
  title: string,
  headers: Record<string, string>,
) {
  if (!nativeModule) {
    throw new Error(
      'Le téléchargement HLS natif est disponible uniquement dans la build iOS, pas dans Expo Go ou l’aperçu web.',
    );
  }

  return nativeModule.startDownload(url, id, title, headers);
}

export async function cancelNativeHlsDownload(id: string) {
  await nativeModule?.cancelDownload(id);
}

export async function deleteNativeHlsDownload(id: string) {
  await nativeModule?.deleteDownload(id);
}

export function addNativeHlsProgressListener(
  listener: (event: OfflineHlsProgressEvent) => void,
) {
  return (
    nativeModule?.addListener('downloadProgress', listener as (event: unknown) => void) ?? {
      remove: () => undefined,
    }
  );
}

export function addNativeHlsCompletedListener(
  listener: (event: OfflineHlsCompletedEvent) => void,
) {
  return (
    nativeModule?.addListener('downloadCompleted', listener as (event: unknown) => void) ?? {
      remove: () => undefined,
    }
  );
}

export function addNativeHlsFailedListener(
  listener: (event: OfflineHlsFailedEvent) => void,
) {
  return (
    nativeModule?.addListener('downloadFailed', listener as (event: unknown) => void) ?? {
      remove: () => undefined,
    }
  );
}