import Foundation

enum AppTab: String {
    case playback
    case offline
}

enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case error

    var label: String {
        switch self {
        case .idle: return "Prêt à lire"
        case .loading: return "Chargement…"
        case .ready: return "Lecture en cours"
        case .error: return "Vidéo indisponible"
        }
    }
}

struct OfflineVideo: Codable, Identifiable, Equatable {
    let id: String
    let sourceURL: String
    let localPath: String
    let filename: String
    let createdAt: Date
    let size: Int64
    let format: String
}

enum DownloadState: Equatable {
    case idle
    case working
}
