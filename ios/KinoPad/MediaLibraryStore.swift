import Foundation

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var sources: [MediaSource] = []
    @Published private(set) var files: [MediaFile] = []
    @Published private(set) var titles: [OfflineTitle] = []
    @Published private(set) var downloadedAssets: [OfflineAssetRecord] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let recordsKey = "mediaFolderBookmarks.v1"
    private let downloadedAssetsKey = "offlineAssetRecords.v1"
    private let internalSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var records: [MediaFolderRecord] = []
    private var scopedURLs: [UUID: (url: URL, didStart: Bool)] = [:]
    private var scanTask: Task<Void, Never>?

    let internalFolderURL: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        internalFolderURL = documents.appendingPathComponent("Movies", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: internalFolderURL,
            withIntermediateDirectories: true
        )

        records = Self.loadRecords(from: defaults, key: recordsKey)
        downloadedAssets = Self.loadDownloadedAssets(from: defaults, key: downloadedAssetsKey)
        resolveSources()
        rescan()
    }

    func addFolders(_ urls: [URL]) {
        var addedAny = false

        for url in urls {
            let normalizedPath = url.standardizedFileURL.path
            if sources.contains(where: { $0.url?.standardizedFileURL.path == normalizedPath }) {
                continue
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let bookmark = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                records.append(
                    MediaFolderRecord(
                        id: UUID(),
                        name: url.lastPathComponent.isEmpty ? "Носитель" : url.lastPathComponent,
                        bookmark: bookmark
                    )
                )
                addedAny = true
            } catch {
                errorMessage = "Не удалось сохранить доступ к папке: \(error.localizedDescription)"
            }
        }

        guard addedAny else { return }
        persistRecords()
        resolveSources()
        rescan()
    }

    func removeSource(id: UUID) {
        guard id != internalSourceID else { return }
        if let scoped = scopedURLs.removeValue(forKey: id), scoped.didStart {
            scoped.url.stopAccessingSecurityScopedResource()
        }
        records.removeAll { $0.id == id }
        persistRecords()
        resolveSources()
        rescan()
    }

    func rescan() {
        resolveSources()
        scanTask?.cancel()
        let currentSources = sources
        let currentDownloads = downloadedAssets
        isScanning = true

        scanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                MediaScanner.scan(sources: currentSources, downloadedAssets: currentDownloads)
            }.value
            guard !Task.isCancelled, let self else { return }
            files = scanned.files
            titles = scanned.titles
            isScanning = false
        }
    }

    func registerDownloadedAsset(_ record: OfflineAssetRecord) {
        downloadedAssets.removeAll {
            $0.catalogID == record.catalogID && $0.season == record.season && $0.episode == record.episode
        }
        downloadedAssets.append(record)
        persistDownloadedAssets()
        rescan()
    }

    func removeDownloadedAsset(id: UUID) {
        guard let record = downloadedAssets.first(where: { $0.id == id }) else { return }
        _ = deleteManagedMedia(records: [record], additionalURLs: [])
    }

    var downloadDestinations: [OfflineDownloadDestination] {
        sources.compactMap { source in
            guard source.isAvailable else { return nil }
            return OfflineDownloadDestination(
                id: source.isInternal ? OfflineDownloadDestination.internalID : source.id.uuidString,
                sourceID: source.isInternal ? nil : source.id,
                name: source.name,
                isInternal: source.isInternal
            )
        }
    }

    func bookmarkData(for destination: OfflineDownloadDestination) -> Data? {
        guard let sourceID = destination.sourceID else { return nil }
        return records.first(where: { $0.id == sourceID })?.bookmark
    }

    func canDeleteFromDevice(title: OfflineTitle, episode: OfflineEpisode) -> Bool {
        !deletableRecords(from: matchingRecords(for: title, episode: episode)).isEmpty ||
            episode.url.map { DeviceMediaOwnership.contains($0, within: internalFolderURL) } == true
    }

    func deletableEpisodeCount(for title: OfflineTitle) -> Int {
        title.episodes.filter { canDeleteFromDevice(title: title, episode: $0) }.count
    }

    @discardableResult
    func deleteFromDevice(title: OfflineTitle, episode: OfflineEpisode) -> Bool {
        let records = deletableRecords(from: matchingRecords(for: title, episode: episode))
        let additionalURLs = [episode.url]
            .compactMap { $0 }
            .filter { DeviceMediaOwnership.contains($0, within: internalFolderURL) }
        return deleteManagedMedia(records: records, additionalURLs: additionalURLs)
    }

    @discardableResult
    func deleteFromDevice(title: OfflineTitle) -> Bool {
        let records = deletableRecords(from: matchingRecords(for: title, episode: nil))
        let additionalURLs = title.episodes
            .compactMap(\.url)
            .filter { DeviceMediaOwnership.contains($0, within: internalFolderURL) }
        return deleteManagedMedia(records: records, additionalURLs: additionalURLs)
    }

    func downloadedEpisodeKeys(for catalogID: String) -> Set<String> {
        let fromRecords = downloadedAssets
            .filter { $0.catalogID == catalogID }
            .map { "\($0.season):\($0.episode)" }
        let fromScan = titles
            .first(where: { $0.catalogID == catalogID })?
            .episodes
            .filter(\.exists)
            .map { "\($0.season):\($0.episode)" } ?? []
        return Set(fromRecords + fromScan)
    }

    private func matchingRecords(for title: OfflineTitle, episode: OfflineEpisode?) -> [OfflineAssetRecord] {
        let exactRecordID: UUID? = episode.flatMap { episode in
            guard episode.id.hasPrefix("download:") else { return nil }
            return UUID(uuidString: String(episode.id.dropFirst("download:".count)))
        }

        return downloadedAssets.filter { record in
            if record.id == exactRecordID { return true }
            guard let catalogID = title.catalogID, record.catalogID == catalogID else { return false }
            guard let episode else { return true }
            return record.season == episode.season && record.episode == episode.episode
        }
    }

    private func deletableRecords(from records: [OfflineAssetRecord]) -> [OfflineAssetRecord] {
        let appHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return records.filter { record in
            guard let url = OfflineAssetLocation.resolve(storedPath: record.localURL) else { return true }
            return DeviceMediaOwnership.contains(url, within: appHome)
        }
    }

    @discardableResult
    private func deleteManagedMedia(records: [OfflineAssetRecord], additionalURLs: [URL]) -> Bool {
        let appHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var recordIDsToRemove = Set<UUID>()
        var deletedPaths = Set<String>()
        var failures: [String] = []
        var removedAnything = false

        for record in records {
            guard let url = OfflineAssetLocation.resolve(storedPath: record.localURL) else {
                recordIDsToRemove.insert(record.id)
                removedAnything = true
                continue
            }
            guard DeviceMediaOwnership.contains(url, within: appHome) else {
                continue
            }

            let path = url.standardizedFileURL.path
            do {
                if deletedPaths.insert(path).inserted, FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(at: url)
                }
                recordIDsToRemove.insert(record.id)
                removedAnything = true
            } catch {
                failures.append(url.lastPathComponent)
            }
        }

        for url in additionalURLs where DeviceMediaOwnership.contains(url, within: internalFolderURL) {
            let path = url.standardizedFileURL.path
            guard deletedPaths.insert(path).inserted, FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removedAnything = true
            } catch {
                failures.append(url.lastPathComponent)
            }
        }

        if !recordIDsToRemove.isEmpty {
            downloadedAssets.removeAll { recordIDsToRemove.contains($0.id) }
            persistDownloadedAssets()
        }
        if removedAnything { rescan() }
        if !failures.isEmpty {
            errorMessage = "Не удалось удалить: \(failures.sorted().joined(separator: ", "))"
        }
        return removedAnything
    }

    private func resolveSources() {
        for scoped in scopedURLs.values where scoped.didStart {
            scoped.url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()

        var resolved: [MediaSource] = [
            MediaSource(
                id: internalSourceID,
                name: "\(AppDevice.internalStorageName) · WooF.Play/Movies",
                url: internalFolderURL,
                isInternal: true
            )
        ]
        var refreshedRecords = records

        for (index, record) in records.enumerated() {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: record.bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let didStart = url.startAccessingSecurityScopedResource()
                scopedURLs[record.id] = (url, didStart)

                let exists = FileManager.default.fileExists(atPath: url.path)
                resolved.append(
                    MediaSource(
                        id: record.id,
                        name: record.name,
                        url: exists ? url : nil,
                        isInternal: false
                    )
                )

                if isStale, exists {
                    refreshedRecords[index].bookmark = try url.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
            } catch {
                resolved.append(
                    MediaSource(
                        id: record.id,
                        name: record.name,
                        url: nil,
                        isInternal: false
                    )
                )
            }
        }

        if refreshedRecords != records {
            records = refreshedRecords
            persistRecords()
        }
        sources = resolved
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: recordsKey)
    }

    private func persistDownloadedAssets() {
        guard let data = try? JSONEncoder().encode(downloadedAssets) else { return }
        defaults.set(data, forKey: downloadedAssetsKey)
    }

    private static func loadRecords(from defaults: UserDefaults, key: String) -> [MediaFolderRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MediaFolderRecord].self, from: data)) ?? []
    }

    private static func loadDownloadedAssets(from defaults: UserDefaults, key: String) -> [OfflineAssetRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([OfflineAssetRecord].self, from: data)) ?? []
    }
}
