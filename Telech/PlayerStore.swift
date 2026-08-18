import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class PlayerStore: ObservableObject {
    @Published var activeTab: AppTab = .playback
    @Published var urlText = URLUtilities.defaultURL
    @Published private(set) var activeURL: String?
    @Published private(set) var activeTitle: String?
    @Published private(set) var history: [String] = []
    @Published private(set) var offlineVideos: [OfflineVideo] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var errorMessage: String?
    @Published var showDetails = false
    @Published private(set) var downloadState: DownloadState = .idle
    @Published private(set) var downloadMessage: String?
    @Published private(set) var downloadProgress: Double?
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showingAlert = false

    let player = AVPlayer()

    private let defaults = UserDefaults.standard
    private let historyKey = "telech.history"
    private let offlineKey = "telech.offline"
    private let maxHistory = 5
    private let downloadManager = DownloadManager()
    private var itemObservation: NSKeyValueObservation?
    private let fileManager = FileManager.default

    var apiBaseURL: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    init() {
        restore()
    }

    func openStream() {
        let candidate = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLUtilities.isValidStreamURL(candidate) else {
            fail("Collez une adresse vidéo complète commençant par http:// ou https://.")
            return
        }

        if let expiry = URLUtilities.signedExpiry(for: candidate), expiry <= Date() {
            activeURL = candidate
            activeTitle = nil
            fail("Ce lien signé a expiré le \(URLUtilities.formatExpiry(expiry)). Demandez un nouveau lien au site source.")
            return
        }

        urlText = candidate
        activeTab = .playback
        showDetails = false
        history = [candidate] + history.filter { $0 != candidate }
        history = Array(history.prefix(maxHistory))
        persistHistory()
        loadVideo(urlString: candidate, title: nil)
    }

    func openRecent(_ value: String) {
        urlText = value
        openStream()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    func downloadActive() {
        let source = (activeURL ?? urlText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard URLUtilities.isValidStreamURL(source) else {
            fail("Collez une adresse vidéo valide avant de télécharger.")
            return
        }
        guard !URLUtilities.isLocal(source) else {
            fail("Cette vidéo est déjà stockée sur l’appareil.")
            return
        }
        if downloadState == .working { return }

        let id = UUID().uuidString.lowercased()
        let folder = offlineFolder.appendingPathComponent(id, isDirectory: true)
        let destination = folder.appendingPathComponent("video.mp4")
        let filename = URLUtilities.filename(from: source) + ".mp4"

        downloadState = .working
        downloadProgress = 0
        downloadMessage = URLUtilities.isHLS(source)
            ? "Conversion et téléchargement de la vidéo…"
            : "Téléchargement de la vidéo…"

        Task {
            do {
                let result = try await downloadManager.download(
                    sourceURL: source,
                    destination: destination,
                    apiBaseURL: apiBaseURL
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }

                let item = OfflineVideo(
                    id: id,
                    sourceURL: source,
                    localPath: result.0.path,
                    filename: filename,
                    createdAt: Date(),
                    size: result.1,
                    format: "mp4"
                )
                if let existing = offlineVideos.first(where: { $0.sourceURL == source }) {
                    removeFiles(for: existing)
                }
                offlineVideos = [item] + offlineVideos.filter { $0.sourceURL != source }
                persistOffline()
                downloadProgress = 1
                downloadMessage = "Vidéo enregistrée. Elle est maintenant disponible dans Hors ligne."
            } catch {
                try? fileManager.removeItem(at: folder)
                downloadMessage = "Téléchargement impossible : \(message(for: error))"
                showAlert(title: "Téléchargement impossible", message: message(for: error))
            }
            downloadState = .idle
        }
    }

    func playOffline(_ video: OfflineVideo) {
        let fileURL = URL(fileURLWithPath: video.localPath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            offlineVideos.removeAll { $0.id == video.id }
            persistOffline()
            showAlert(title: "Fichier indisponible", message: "Cette vidéo locale n’existe plus dans le stockage de l’app.")
            return
        }
        activeTab = .playback
        urlText = video.sourceURL
        downloadMessage = nil
        loadVideo(urlString: fileURL.absoluteString, title: video.filename)
    }

    func removeOffline(_ video: OfflineVideo) {
        removeFiles(for: video)
        offlineVideos.removeAll { $0.id == video.id }
        persistOffline()
    }

    func loadVideo(urlString: String, title: String?) {
        guard let url = URL(string: urlString) else {
            fail("Impossible de lire cette adresse vidéo.")
            return
        }
        if URLUtilities.isLocal(urlString) && !fileManager.fileExists(atPath: url.path) {
            fail("Le fichier vidéo local est introuvable.")
            return
        }

        activeURL = urlString
        activeTitle = title
        playbackState = .loading
        errorMessage = nil
        let options: [String: Any] = URLUtilities.isLocal(urlString)
            ? [:]
            : [AVURLAssetHTTPHeaderFieldsKey: URLUtilities.headers(for: urlString)]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.playbackState = .ready
                    self.errorMessage = nil
                case .failed:
                    self.fail(item.error?.localizedDescription ?? "Impossible de charger cette vidéo.")
                default:
                    self.playbackState = .loading
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func failureTitle() -> String {
        if let activeURL,
           let expiry = URLUtilities.signedExpiry(for: activeURL),
           expiry <= Date() {
            return "Le lien a expiré"
        }
        if errorMessage?.contains("403") == true {
            return "Accès refusé par le site source"
        }
        return "Lecture refusée"
    }

    func failureExplanation() -> String {
        if let activeURL,
           let expiry = URLUtilities.signedExpiry(for: activeURL),
           expiry <= Date() {
            return "Collez un nouveau lien généré par le site source."
        }
        return "Le lecteur autonome ne passe pas par un relais serveur : le site source doit autoriser l’accès direct."
    }

    private var offlineFolder: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("offline-videos", isDirectory: true)
    }

    private func restore() {
        if let data = defaults.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            history = Array(saved.prefix(maxHistory))
        }
        if let data = defaults.data(forKey: offlineKey),
           let saved = try? JSONDecoder().decode([OfflineVideo].self, from: data) {
            offlineVideos = saved.filter { fileManager.fileExists(atPath: $0.localPath) }
            persistOffline()
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func persistOffline() {
        if let data = try? JSONEncoder().encode(offlineVideos) {
            defaults.set(data, forKey: offlineKey)
        }
    }

    private func removeFiles(for video: OfflineVideo) {
        let fileURL = URL(fileURLWithPath: video.localPath)
        try? fileManager.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func fail(_ message: String) {
        playbackState = .error
        errorMessage = message
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    private func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        let nsError = error as NSError
        if nsError.code == NSURLErrorNotConnectedToInternet {
            return "Aucune connexion réseau n’est disponible."
        }
        if nsError.code == NSURLErrorTimedOut {
            return "Le serveur source met trop de temps à répondre."
        }
        return error.localizedDescription
    }
}
