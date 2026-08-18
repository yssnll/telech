import Foundation

enum URLUtilities {
    static let defaultURL =
        "https://video.sibnet.ru/v/b85c60dd8c85fd25641a21fbcbb3d20c/6223248.m3u8"

    static func isValidStreamURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    static func isHLS(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return value.lowercased().contains(".m3u8")
        }
        return url.path.lowercased().hasSuffix(".m3u8")
    }

    static func isLocal(_ value: String) -> Bool {
        value.hasPrefix("file://") || value.hasPrefix("/")
    }

    static func shortened(_ value: String) -> String {
        guard let url = URL(string: value) else {
            return value.count > 34 ? String(value.prefix(34)) + "…" : value
        }
        let path = url.path
        let clipped = path.count > 24 ? String(path.prefix(24)) + "…" : path
        return "\(url.host ?? value)\(clipped)"
    }

    static func filename(from value: String, fallback: String = "video") -> String {
        if let url = URL(string: value),
           let last = url.pathComponents.last,
           !last.isEmpty {
            let decoded = last.removingPercentEncoding ?? last
            let withoutExtension = decoded.replacingOccurrences(
                of: #"\.(m3u8|mp4|m4v|mov|ts)$"#,
                with: "",
                options: .regularExpression
            )
            let safe = withoutExtension
                .replacingOccurrences(of: #"[^a-zA-Z0-9\-_ ]"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !safe.isEmpty {
                return String(safe.prefix(60))
            }
        }
        return fallback
    }

    static func headers(for value: String) -> [String: String] {
        guard let url = URL(string: value), let host = url.host?.lowercased() else {
            return ["Accept": "*/*", "User-Agent": userAgent]
        }

        var headers = ["Accept": "*/*", "User-Agent": userAgent]
        if host == "video.sibnet.ru" || host.hasSuffix(".sibnet.ru") {
            headers["Referer"] = "https://video.sibnet.ru/"
            headers["Origin"] = "https://video.sibnet.ru"
            headers["Accept-Language"] = "fr-FR,fr;q=0.9,en;q=0.8"
        }
        if host == "uqload.vc" || host.hasSuffix(".uqload.vc") {
            headers["Referer"] = "https://uqload.to/"
            headers["Origin"] = "https://uqload.to"
            headers["Accept-Language"] = "fr-FR,fr;q=0.9,en;q=0.8"
        }
        if host == "vmpx.online" || host.hasSuffix(".vmpx.online") {
            headers["Referer"] = "https://vmpx.online/"
            headers["Origin"] = "https://vmpx.online"
            headers["Accept-Language"] = "fr-FR,fr;q=0.9,en;q=0.8"
        }
        return headers
    }

    static func signedExpiry(for value: String) -> Date? {
        guard let url = URL(string: value),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let startString = query.first(where: { $0.name == "s" })?.value,
              let start = Double(startString),
              start > 0 else {
            return nil
        }

        guard let endString = query.first(where: { $0.name == "e" })?.value,
              let endOrDuration = Double(endString),
              endOrDuration > 0 else {
            return nil
        }
        let end = endOrDuration >= 1_000_000_000 ? endOrDuration : start + endOrDuration
        return Date(timeIntervalSince1970: end)
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_BE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func formatBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: value)
    }

    static func formatExpiry(_ date: Date) -> String {
        formatDate(date)
    }

    static var userAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
    }
}
