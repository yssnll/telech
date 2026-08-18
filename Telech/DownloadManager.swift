import Foundation

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var state: DownloadState = .idle
    @Published private(set) var progress: Double?
    @Published private(set) var message: String?

    private var session: URLSession!
    private var completion: ((Result<(URL, Int64), Error>) -> Void)?
    private var destination: URL?
    private var progressHandler: ((Double?) -> Void)?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func download(
        sourceURL: String,
        destination: URL,
        apiBaseURL: String?,
        onProgress: @escaping (Double?) -> Void
    ) async throws -> (URL, Int64) {
        guard let source = URL(string: sourceURL) else {
            throw DownloadError.invalidURL
        }

        if state == .working {
            throw DownloadError.alreadyDownloading
        }

        state = .working
        progress = 0
        message = URLUtilities.isHLS(sourceURL)
            ? "Conversion et téléchargement de la vidéo…"
            : "Téléchargement de la vidéo…"
        self.destination = destination
        progressHandler = onProgress

        var requestURL = source
        if URLUtilities.isHLS(sourceURL) {
            guard let apiBaseURL,
                  let base = URL(string: normalizedBase(apiBaseURL)) else {
                reset()
                throw DownloadError.missingAPIBaseURL
            }
            var components = URLComponents(
                url: base.appendingPathComponent("api/downloads/mp4"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "url", value: sourceURL),
                URLQueryItem(name: "mode", value: "compatible")
            ]
            guard let converted = components?.url else {
                reset()
                throw DownloadError.invalidAPIBaseURL
            }
            requestURL = converted
        }

        var request = URLRequest(url: requestURL)
        URLUtilities.headers(for: sourceURL).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if URLUtilities.isHLS(sourceURL) {
            request.setValue("video/mp4", forHTTPHeaderField: "Accept")
        }

        return try await withCheckedThrowingContinuation { continuation in
            completion = { [weak self] result in
                self?.reset()
                continuation.resume(with: result)
            }
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func cancel() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        Task { @MainActor in
            self.reset()
        }
    }

    private func normalizedBase(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            return String(trimmed.dropLast())
        }
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
    }

    private func reset() {
        state = .idle
        progress = nil
        destination = nil
        progressHandler = nil
        completion = nil
    }

    private func fail(_ error: Error) {
        let callback = completion
        completion = nil
        callback?(.failure(error))
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let value = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        Task { @MainActor in
            self.progress = value
            self.progressHandler?(value)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            if let statusCode, !(200..<300).contains(statusCode) {
                self.fail(DownloadError.httpStatus(statusCode))
                return
            }
            guard let destination = self.destination else {
                self.fail(DownloadError.missingDestination)
                return
            }
            do {
                let folder = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else {
                    self.fail(DownloadError.emptyFile)
                    return
                }
                self.progress = 1
                self.completion?(.success((destination, size)))
            } catch {
                self.fail(error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            self.fail(error)
        }
    }
}

enum DownloadError: LocalizedError {
    case invalidURL
    case alreadyDownloading
    case missingAPIBaseURL
    case invalidAPIBaseURL
    case missingDestination
    case emptyFile
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "L’adresse vidéo est invalide."
        case .alreadyDownloading:
            return "Un téléchargement est déjà en cours."
        case .missingAPIBaseURL:
            return "Le domaine de conversion HLS n’est pas configuré pour cette app."
        case .invalidAPIBaseURL:
            return "Le domaine de conversion HLS est invalide."
        case .missingDestination:
            return "Le fichier de destination est indisponible."
        case .emptyFile:
            return "Le fichier vidéo reçu est vide ou indisponible."
        case let .httpStatus(status):
            if status == 403 {
                return "Le serveur source a refusé la requête (HTTP 403). Le lien peut être expiré ou lié à une page d’origine."
            }
            return "Le serveur vidéo a répondu HTTP \(status)."
        }
    }
}
