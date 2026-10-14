import AVFoundation
import Foundation

enum OfflineDownloadStatus: String, Sendable {
    case waiting
    case downloading
    case finished
    case failed
}

struct OfflineDownloadJob: Identifiable, Equatable, Sendable {
    let id: String
    let catalogID: String
    let title: String
    let season: Int
    let episode: Int
    var progress: Double
    var status: OfflineDownloadStatus
    var errorMessage: String?
    let optionSummary: String?

    var episodeLabel: String {
        season > 0 ? "S\(season) E\(episode)" : "Фильм"
    }
}

private struct OfflineDownloadMetadata: Codable, Sendable {
    let catalogID: String
    let title: String
    let originalTitle: String?
    let posterURL: String?
    let type: String
    let genres: [String]
    let season: Int
    let episode: Int
    let episodeTitle: String
    let quality: String?
    let audioTrack: String?
    let destinationName: String?
    let destinationBookmark: Data?

    func record(localURL: URL) -> OfflineAssetRecord {
        OfflineAssetRecord(
            id: UUID(), catalogID: catalogID, title: title, originalTitle: originalTitle,
            posterURL: posterURL, type: type, genres: genres, season: season, episode: episode,
            episodeTitle: episodeTitle,
            localURL: OfflineAssetLocation.persistedPath(for: localURL),
            downloadedAt: Date()
        )
    }
}

private struct DownloadLocationResult: Sendable {
    let url: URL?
    let warning: String?
}

private final class DownloadLocationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: DownloadLocationResult] = [:]

    func set(_ result: DownloadLocationResult, for taskID: String) {
        lock.lock()
        values[taskID] = result
        lock.unlock()
    }

    func take(taskID: String) -> DownloadLocationResult? {
        lock.lock()
        defer { lock.unlock() }
        return values.removeValue(forKey: taskID)
    }
}

@MainActor
final class OfflineDownloadManager: NSObject, ObservableObject {
    @Published private(set) var jobs: [OfflineDownloadJob] = []
    @Published private(set) var preparing: Set<String> = []

    private unowned let library: MediaLibraryStore
    private let locations = DownloadLocationRegistry()
    private static var backgroundSessionPrefix: String {
        Bundle.main.bundleIdentifier ?? "app.xigua7648.gray5696"
    }

    private lazy var downloadSession: AVAssetDownloadURLSession = {
        let identifier = "\(Self.backgroundSessionPrefix).offline-hls"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.allowsCellularAccess = true
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: nil
        )
    }()
    private lazy var fileDownloadSession: URLSession = {
        let identifier = "\(Self.backgroundSessionPrefix).offline-files"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.allowsCellularAccess = true
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(library: MediaLibraryStore) {
        self.library = library
        super.init()
        restoreTasks()
    }

    func enqueue(
        item: CatalogItem,
        media: PlayableMedia,
        variant: DownloadVariant? = nil,
        audioTrackIndex: Int? = nil,
        destination: OfflineDownloadDestination? = nil
    ) {
        let key = "\(media.season):\(media.episode)"
        guard !library.downloadedEpisodeKeys(for: item.id.value).contains(key),
              !preparing.contains("\(item.id.value):\(key)"),
              !jobs.contains(where: {
                  $0.catalogID == item.id.value && $0.season == media.season && $0.episode == media.episode && $0.status != .failed
              })
        else { return }

        let selectedVariant = variant ?? media.downloadVariants.first ?? DownloadVariant(
            label: "Авто", width: nil, height: nil, codec: nil,
            manifestURL: media.manifestURL, directFileURL: nil
        )
        let selectedAudio = audioTrackIndex.flatMap { index in
            let tracks = media.audioTracks.sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
            return tracks.indices.contains(index) ? tracks[index] : nil
        }
        let resolvedDestination = destination ?? library.downloadDestinations.first(where: \.isInternal)

        let metadata = OfflineDownloadMetadata(
            catalogID: item.id.value,
            title: item.displayTitle,
            originalTitle: item.originalTitle,
            posterURL: item.posters?.bestURL?.absoluteString,
            type: item.type ?? (media.season > 0 ? "serial" : "movie"),
            genres: item.genres?.compactMap(\.title) ?? [],
            season: media.season,
            episode: media.episode,
            episodeTitle: media.title,
            quality: selectedVariant.displayName,
            audioTrack: selectedAudio?.displayName,
            destinationName: resolvedDestination?.name,
            destinationBookmark: resolvedDestination.flatMap(library.bookmarkData)
        )

        if resolvedDestination?.isInternal == false {
            guard let directURL = selectedVariant.directFileURL else {
                appendFailedJob(
                    item: item,
                    media: media,
                    message: "Для этого качества сервер не предоставил файл для сохранения на внешний диск"
                )
                return
            }
            createFileDownload(url: directURL, metadata: metadata)
            return
        }

        let preparationKey = "\(item.id.value):\(key)"
        preparing.insert(preparationKey)
        Task { [weak self] in
            guard let self else { return }
            defer { preparing.remove(preparationKey) }
            await createHLSDownload(
                manifestURL: selectedVariant.manifestURL,
                metadata: metadata,
                audioTrackIndex: audioTrackIndex
            )
        }
    }

    private func createHLSDownload(
        manifestURL: URL,
        metadata: OfflineDownloadMetadata,
        audioTrackIndex: Int?
    ) async {
        let asset = AVURLAsset(url: manifestURL)
        var options: [String: Any] = [:]
        if let audioTrackIndex,
           let group = try? await asset.loadMediaSelectionGroup(for: .audible),
           group.options.indices.contains(audioTrackIndex) {
            guard let preferredSelection = try? await asset.load(.preferredMediaSelection),
                  let mediaSelection = preferredSelection.mutableCopy() as? AVMutableMediaSelection
            else {
                appendFailedJob(metadata: metadata, message: "Не удалось выбрать аудиодорожку")
                return
            }
            mediaSelection.select(group.options[audioTrackIndex], in: group)
            options[AVAssetDownloadTaskMediaSelectionKey] = mediaSelection
        }
        guard let task = downloadSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "\(metadata.title) · \(metadata.episodeTitle)",
            assetArtworkData: nil,
            options: options.isEmpty ? nil : options
        ) else {
            appendFailedJob(metadata: metadata, message: "Не удалось создать задачу загрузки")
            return
        }

        if let data = try? JSONEncoder().encode(metadata) {
            task.taskDescription = data.base64EncodedString()
        }
        jobs.append(OfflineDownloadJob(
            id: Self.jobID(session: downloadSession, taskID: task.taskIdentifier), catalogID: metadata.catalogID, title: metadata.title,
            season: metadata.season, episode: metadata.episode,
            progress: 0, status: .waiting, errorMessage: nil,
            optionSummary: Self.optionSummary(metadata)
        ))
        task.resume()
        updateJob(id: Self.jobID(session: downloadSession, taskID: task.taskIdentifier)) { $0.status = .downloading }
    }

    private func createFileDownload(url: URL, metadata: OfflineDownloadMetadata) {
        let task = fileDownloadSession.downloadTask(with: url)
        if let data = try? JSONEncoder().encode(metadata) {
            task.taskDescription = data.base64EncodedString()
        }
        let id = Self.jobID(session: fileDownloadSession, taskID: task.taskIdentifier)
        jobs.append(OfflineDownloadJob(
            id: id, catalogID: metadata.catalogID, title: metadata.title,
            season: metadata.season, episode: metadata.episode,
            progress: 0, status: .waiting, errorMessage: nil,
            optionSummary: Self.optionSummary(metadata)
        ))
        task.resume()
        updateJob(id: id) { $0.status = .downloading }
    }

    func enqueueMissing(item: CatalogItem) {
        let downloaded = library.downloadedEpisodeKeys(for: item.id.value)
        for media in item.playableItems where !downloaded.contains("\(media.season):\(media.episode)") {
            enqueue(item: item, media: media)
        }
    }

    func cancel(jobID: String) {
        for session in [downloadSession as URLSession, fileDownloadSession] {
            session.getAllTasks { tasks in
                tasks.first(where: { Self.jobID(session: session, taskID: $0.taskIdentifier) == jobID })?.cancel()
            }
        }
    }

    func isQueued(catalogID: String, season: Int, episode: Int) -> Bool {
        jobs.contains {
            $0.catalogID == catalogID && $0.season == season && $0.episode == episode &&
                ($0.status == .waiting || $0.status == .downloading)
        } || preparing.contains("\(catalogID):\(season):\(episode)")
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .finished || $0.status == .failed }
    }

    private func restoreTasks() {
        restoreTasks(in: downloadSession)
        restoreTasks(in: fileDownloadSession)
    }

    private func restoreTasks(in session: URLSession) {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let metadata = Self.metadata(from: task),
                          !self.jobs.contains(where: { $0.id == Self.jobID(session: session, taskID: task.taskIdentifier) })
                    else { continue }
                    self.jobs.append(OfflineDownloadJob(
                        id: Self.jobID(session: session, taskID: task.taskIdentifier), catalogID: metadata.catalogID, title: metadata.title,
                        season: metadata.season, episode: metadata.episode,
                        progress: task.progress.fractionCompleted,
                        status: task.state == .running ? .downloading : .waiting,
                        errorMessage: nil,
                        optionSummary: Self.optionSummary(metadata)
                    ))
                }
            }
        }
    }

    private func updateJob(id: String, _ change: (inout OfflineDownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    nonisolated private static func metadata(from task: URLSessionTask) -> OfflineDownloadMetadata? {
        guard let description = task.taskDescription,
              let data = Data(base64Encoded: description)
        else { return nil }
        return try? JSONDecoder().decode(OfflineDownloadMetadata.self, from: data)
    }

    nonisolated private static func jobID(session: URLSession, taskID: Int) -> String {
        "\(session.configuration.identifier ?? "download"):\(taskID)"
    }

    nonisolated private static func optionSummary(_ metadata: OfflineDownloadMetadata) -> String? {
        let summary = [metadata.quality, metadata.audioTrack, metadata.destinationName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    private func appendFailedJob(item: CatalogItem, media: PlayableMedia, message: String) {
        let metadata = OfflineDownloadMetadata(
            catalogID: item.id.value, title: item.displayTitle, originalTitle: item.originalTitle,
            posterURL: item.posters?.bestURL?.absoluteString, type: item.type ?? "movie",
            genres: item.genres?.compactMap(\.title) ?? [], season: media.season, episode: media.episode,
            episodeTitle: media.title, quality: nil, audioTrack: nil, destinationName: nil, destinationBookmark: nil
        )
        appendFailedJob(metadata: metadata, message: message)
    }

    private func appendFailedJob(metadata: OfflineDownloadMetadata, message: String) {
        jobs.append(OfflineDownloadJob(
            id: "failed:\(UUID().uuidString)", catalogID: metadata.catalogID, title: metadata.title,
            season: metadata.season, episode: metadata.episode, progress: 0, status: .failed,
            errorMessage: message, optionSummary: Self.optionSummary(metadata)
        ))
    }
}

extension OfflineDownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in KinoPadAppDelegate.finishBackgroundEvents() }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let expected = timeRangeExpectedToLoad.duration.seconds
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let progress = expected > 0 ? min(max(loaded / expected, 0), 1) : assetDownloadTask.progress.fractionCompleted
        let id = Self.jobID(session: session, taskID: assetDownloadTask.taskIdentifier)
        Task { @MainActor [weak self] in
            self?.updateJob(id: id) {
                $0.progress = progress
                $0.status = .downloading
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        let id = Self.jobID(session: session, taskID: assetDownloadTask.taskIdentifier)
        locations.set(DownloadLocationResult(url: location, warning: nil), for: id)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let id = Self.jobID(session: session, taskID: assetDownloadTask.taskIdentifier)
        locations.set(DownloadLocationResult(url: location, warning: nil), for: id)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction = totalBytesExpectedToWrite > 0
            ? min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
            : downloadTask.progress.fractionCompleted
        let id = Self.jobID(session: session, taskID: downloadTask.taskIdentifier)
        Task { @MainActor [weak self] in
            self?.updateJob(id: id) {
                $0.progress = fraction
                $0.status = .downloading
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let id = Self.jobID(session: session, taskID: downloadTask.taskIdentifier)
        guard let metadata = Self.metadata(from: downloadTask) else {
            locations.set(
                DownloadLocationResult(url: location, warning: "Не удалось прочитать параметры загрузки"),
                for: id
            )
            return
        }

        do {
            let savedURL = try Self.moveDownloadedFile(
                from: location,
                suggestedFilename: downloadTask.response?.suggestedFilename,
                metadata: metadata
            )
            locations.set(DownloadLocationResult(url: savedURL, warning: nil), for: id)
        } catch {
            do {
                let fallbackURL = try Self.moveToInternalFolder(
                    from: location,
                    suggestedFilename: downloadTask.response?.suggestedFilename,
                    metadata: metadata
                )
                locations.set(
                    DownloadLocationResult(
                        url: fallbackURL,
                        warning: "Внешний диск недоступен. Видео сохранено на \(AppDevice.platformName): \(error.localizedDescription)"
                    ),
                    for: id
                )
            } catch {
                locations.set(
                    DownloadLocationResult(url: nil, warning: "Не удалось сохранить загруженный файл: \(error.localizedDescription)"),
                    for: id
                )
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let id = Self.jobID(session: session, taskID: task.taskIdentifier)
        let result = locations.take(taskID: id)
        let metadata = Self.metadata(from: task)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.updateJob(id: id) {
                    $0.status = .failed
                    $0.errorMessage = error.localizedDescription
                }
                return
            }
            guard let result, let metadata else {
                self.updateJob(id: id) {
                    $0.status = .failed
                    $0.errorMessage = "Система не вернула путь к загруженному видео"
                }
                return
            }
            guard let localURL = result.url else {
                self.updateJob(id: id) {
                    $0.status = .failed
                    $0.errorMessage = result.warning ?? "Не удалось сохранить загруженное видео"
                }
                return
            }
            self.library.registerDownloadedAsset(metadata.record(localURL: localURL))
            self.updateJob(id: id) {
                $0.progress = 1
                $0.status = .finished
                $0.errorMessage = result.warning
            }
        }
    }

    nonisolated private static func moveDownloadedFile(
        from temporaryURL: URL,
        suggestedFilename: String?,
        metadata: OfflineDownloadMetadata
    ) throws -> URL {
        guard let bookmark = metadata.destinationBookmark else {
            throw CocoaError(.fileNoSuchFile)
        }
        var stale = false
        let root = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        return try move(
            from: temporaryURL,
            toRoot: root.appendingPathComponent("WooF.Play", isDirectory: true),
            suggestedFilename: suggestedFilename,
            metadata: metadata
        )
    }

    nonisolated private static func moveToInternalFolder(
        from temporaryURL: URL,
        suggestedFilename: String?,
        metadata: OfflineDownloadMetadata
    ) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return try move(
            from: temporaryURL,
            toRoot: documents.appendingPathComponent("Movies", isDirectory: true),
            suggestedFilename: suggestedFilename,
            metadata: metadata
        )
    }

    nonisolated private static func move(
        from temporaryURL: URL,
        toRoot root: URL,
        suggestedFilename: String?,
        metadata: OfflineDownloadMetadata
    ) throws -> URL {
        let fileManager = FileManager.default
        let titleFolder = root.appendingPathComponent(safeFilename(metadata.title), isDirectory: true)
        try fileManager.createDirectory(at: titleFolder, withIntermediateDirectories: true)
        let episodePrefix = metadata.season > 0
            ? String(format: "S%02dE%02d", metadata.season, metadata.episode)
            : "Movie"
        let suggestedExtension = URL(fileURLWithPath: suggestedFilename ?? temporaryURL.lastPathComponent).pathExtension
        let ext = suggestedExtension.isEmpty ? "mp4" : suggestedExtension
        let baseName = "\(episodePrefix) - \(safeFilename(metadata.episodeTitle))"
        var destination = titleFolder.appendingPathComponent(baseName).appendingPathExtension(ext)
        if fileManager.fileExists(atPath: destination.path) {
            destination = titleFolder
                .appendingPathComponent("\(baseName) - \(UUID().uuidString.prefix(6))")
                .appendingPathExtension(ext)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Видео" : cleaned
    }
}
