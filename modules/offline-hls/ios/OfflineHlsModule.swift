import AVFoundation
import ExpoModulesCore

private struct HLSDownloadInfo {
  let id: String
  let title: String
  let destination: URL
}

public final class OfflineHlsModule: Module, AVAssetDownloadDelegate {
  private let sessionIdentifier = "com.anonymous.hls-video-player.offline-hls"
  private let stateQueue = DispatchQueue(label: "com.anonymous.hls-video-player.offline-hls.state")
  private var downloadSession: AVAssetDownloadURLSession?
  private var downloadInfo: [Int: HLSDownloadInfo] = [:]
  private var progressByTask: [Int: Double] = [:]
  private var completedTasks = Set<Int>()

  public func definition() -> ModuleDefinition {
    Name("OfflineHls")

    Events("downloadProgress", "downloadCompleted", "downloadFailed")

    OnCreate {
      self.createDownloadSession()
    }

    AsyncFunction("startDownload") {
      (urlString: String, id: String, title: String, headers: [String: String]?) throws -> [String: String] in
      guard
        let url = URL(string: urlString),
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https"
      else {
        throw HLSDownloadError.invalidURL
      }

      guard let session = self.downloadSession else {
        throw HLSDownloadError.sessionUnavailable
      }

      var assetOptions: [String: Any] = [:]
      if let headers, !headers.isEmpty {
        assetOptions[AVURLAssetHTTPHeaderFieldsKey] = headers
      }

      let asset = AVURLAsset(url: url, options: assetOptions)
      let destination = try self.destinationURL(for: id)
      let task = session.makeAssetDownloadTask(
        asset: asset,
        assetTitle: title.isEmpty ? "Vidéo" : title,
        assetArtworkData: nil,
        options: nil
      )

      guard let task else {
        throw HLSDownloadError.taskCreationFailed
      }

      task.taskDescription = id
      self.stateQueue.sync {
        self.downloadInfo[task.taskIdentifier] = HLSDownloadInfo(
          id: id,
          title: title,
          destination: destination
        )
        self.progressByTask[task.taskIdentifier] = 0
        self.completedTasks.remove(task.taskIdentifier)
      }
      task.resume()

      return ["id": id]
    }

    AsyncFunction("cancelDownload") { (id: String) in
      self.downloadSession?.getAllTasks { tasks in
        tasks
          .filter { $0.taskDescription == id }
          .forEach { $0.cancel() }
      }
    }

    AsyncFunction("deleteDownload") { (id: String) throws in
      let destination = try self.destinationURL(for: id)
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
    }
  }

  private func createDownloadSession() {
    let configuration = AVAssetDownloadURLSessionConfiguration.background(
      withIdentifier: sessionIdentifier
    )
    configuration.httpMaximumConnectionsPerHost = 8
    let delegateQueue = OperationQueue()
    delegateQueue.maxConcurrentOperationCount = 1
    delegateQueue.qualityOfService = .userInitiated
    downloadSession = AVAssetDownloadURLSession(
      configuration: configuration,
      assetDownloadDelegate: self,
      delegateQueue: delegateQueue
    )
  }

  private func destinationURL(for id: String) throws -> URL {
    guard
      id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    else {
      throw HLSDownloadError.invalidIdentifier
    }

    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let directory = applicationSupport.appendingPathComponent("OfflineHls", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return directory.appendingPathComponent("\(id).movpkg", isDirectory: true)
  }

  private func info(for task: AVAssetDownloadTask) -> HLSDownloadInfo? {
    stateQueue.sync {
      downloadInfo[task.taskIdentifier]
    }
  }

  private func sendFailure(for task: URLSessionTask, message: String) {
    guard let id = task.taskDescription, !id.isEmpty else {
      return
    }
    sendEvent("downloadFailed", [
      "id": id,
      "message": message
    ])
  }

  private func directorySize(at url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      if
        let values = try? fileURL.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true
      {
        size += Int64(values.fileSize ?? 0)
      }
    }
    return size
  }

  public func urlSession(
    _ session: AVAssetDownloadURLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didLoad timeRange: CMTimeRange,
    totalTimeRange: CMTimeRange
  ) {
    guard let info = info(for: assetDownloadTask) else {
      return
    }

    let totalSeconds = totalTimeRange.duration.seconds
    let loadedSeconds = timeRange.duration.seconds
    guard totalSeconds.isFinite, totalSeconds > 0, loadedSeconds.isFinite else {
      return
    }

    let candidate = min(0.99, max(0, loadedSeconds / totalSeconds))
    let progress = stateQueue.sync {
      let previous = progressByTask[assetDownloadTask.taskIdentifier] ?? 0
      let next = max(previous, candidate)
      progressByTask[assetDownloadTask.taskIdentifier] = next
      return next
    }

    sendEvent("downloadProgress", [
      "id": info.id,
      "progress": progress
    ])
  }

  public func urlSession(
    _ session: AVAssetDownloadURLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let info = info(for: assetDownloadTask) else {
      return
    }

    do {
      if FileManager.default.fileExists(atPath: info.destination.path) {
        try FileManager.default.removeItem(at: info.destination)
      }
      try FileManager.default.moveItem(at: location, to: info.destination)
      let size = directorySize(at: info.destination)

      stateQueue.sync {
        completedTasks.insert(assetDownloadTask.taskIdentifier)
      }
      sendEvent("downloadProgress", [
        "id": info.id,
        "progress": 1
      ])
      sendEvent("downloadCompleted", [
        "id": info.id,
        "localUri": info.destination.absoluteString,
        "size": size
      ])
    } catch {
      sendFailure(for: assetDownloadTask, message: error.localizedDescription)
    }
  }

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else {
      return
    }

    let alreadyCompleted = stateQueue.sync {
      completedTasks.contains(task.taskIdentifier)
    }
    if !alreadyCompleted {
      sendFailure(for: task, message: error.localizedDescription)
    }
  }

  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    HLSBackgroundEvents.shared.complete()
  }
}

private enum HLSDownloadError: Error {
  case invalidURL
  case invalidIdentifier
  case sessionUnavailable
  case taskCreationFailed
}

private final class HLSBackgroundEvents {
  static let shared = HLSBackgroundEvents()

  private let lock = NSLock()
  private var completionHandler: (() -> Void)?

  func store(_ handler: @escaping () -> Void) {
    lock.lock()
    completionHandler = handler
    lock.unlock()
  }

  func complete() {
    lock.lock()
    let handler = completionHandler
    completionHandler = nil
    lock.unlock()
    handler?()
  }
}

public final class OfflineHlsAppDelegateSubscriber: ExpoAppDelegateSubscriber {
  public func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == "com.anonymous.hls-video-player.offline-hls" else {
      return
    }
    HLSBackgroundEvents.shared.store(completionHandler)
  }
}