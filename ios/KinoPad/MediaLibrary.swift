import Foundation

struct MediaFile: Identifiable, Hashable, Sendable {
    let url: URL
    let byteCount: Int64?
    let modifiedAt: Date?
    let sourceName: String

    init(url: URL, byteCount: Int64?, modifiedAt: Date?, sourceName: String = "") {
        self.url = url
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.sourceName = sourceName
    }

    var id: URL { url.standardizedFileURL }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    var isSystemPlayable: Bool { Self.systemPlayableExtensions.contains(fileExtension) }

    var formattedSize: String? {
        guard let byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    static let systemPlayableExtensions: Set<String> = ["mp4", "m4v", "mov", "ts", "movpkg"]
}

struct MediaFolderRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var bookmark: Data
}

struct MediaSource: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL?
    let isInternal: Bool

    var isAvailable: Bool { url != nil }
}

struct OfflineDownloadDestination: Identifiable, Hashable, Sendable {
    static let internalID = "internal"

    let id: String
    let sourceID: UUID?
    let name: String
    let isInternal: Bool
}

struct OfflineEpisode: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL?
    let season: Int
    let episode: Int
    let title: String
    let byteCount: Int64?
    let modifiedAt: Date?
    let resolution: String?
    let sourceName: String
    let isSystemPlayable: Bool

    var displayNumber: String? {
        guard season > 0 || episode > 0 else { return nil }
        return season > 0 ? "S\(season) E\(episode)" : "Видео \(episode)"
    }

    var progressKey: String { "offline:\(id)" }
    var exists: Bool { url != nil }
}

struct OfflineTitle: Identifiable, Hashable, Sendable {
    let id: String
    let catalogID: String?
    let title: String
    let originalTitle: String?
    let summary: String?
    let posterURL: URL?
    let type: String
    let genres: [String]
    let updatedAt: Date?
    let episodes: [OfflineEpisode]

    var isMovie: Bool { type.lowercased().contains("movie") || (episodes.count == 1 && episodes[0].season == 0) }
    var availableCount: Int { episodes.filter(\.exists).count }
    var totalBytes: Int64 { episodes.compactMap(\.byteCount).reduce(0, +) }
    var seasonCount: Int { Set(episodes.map(\.season).filter { $0 > 0 }).count }

    var subtitle: String {
        if isMovie { return "Фильм" }
        if seasonCount > 1 { return "Сериал · \(seasonCount) сезона · \(availableCount) эп." }
        return "Сериал · \(availableCount) эп."
    }
}

struct OfflineAssetRecord: Codable, Hashable, Sendable {
    let id: UUID
    let catalogID: String
    let title: String
    let originalTitle: String?
    let posterURL: String?
    let type: String
    let genres: [String]
    let season: Int
    let episode: Int
    let episodeTitle: String
    let localURL: String
    let downloadedAt: Date
}

enum OfflineAssetLocation {
    static func persistedPath(
        for url: URL,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> String {
        let path = removingNoFollowPrefix(from: url.path)
        if let relative = containerRelativePath(in: path) {
            return relative
        }

        let homePath = homeDirectory.standardizedFileURL.path
        if path.hasPrefix(homePath + "/") {
            return String(path.dropFirst(homePath.count + 1))
        }
        return path
    }

    static func resolve(
        storedPath: String,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL? {
        let normalized = removingNoFollowPrefix(from: storedPath)
        var candidates: [URL] = []

        if normalized.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: normalized))
        } else {
            candidates.append(homeDirectory.appendingPathComponent(normalized))
        }

        if let relative = containerRelativePath(in: normalized) {
            candidates.append(homeDirectory.appendingPathComponent(relative))
            if let decoded = relative.removingPercentEncoding, decoded != relative {
                candidates.append(homeDirectory.appendingPathComponent(decoded))
            }
        }

        var seen = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            return seen.insert(path).inserted && FileManager.default.fileExists(atPath: path)
        }
    }

    private static func removingNoFollowPrefix(from path: String) -> String {
        guard path.hasPrefix("/.nofollow/") else { return path }
        return String(path.dropFirst("/.nofollow".count))
    }

    private static func containerRelativePath(in path: String) -> String? {
        for root in ["Library", "Documents", "tmp"] {
            let marker = "/\(root)/"
            if let range = path.range(of: marker) {
                return root + "/" + path[range.upperBound...]
            }
        }
        return nil
    }
}

enum DeviceMediaOwnership {
    static func contains(_ url: URL, within root: URL) -> Bool {
        let candidatePath = canonicalPath(for: url)
        let rootPath = canonicalPath(for: root)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func canonicalPath(for url: URL) -> String {
        let fileManager = FileManager.default
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor = parent
        }

        var resolved = existingAncestor.resolvingSymlinksInPath()
        for component in missingComponents {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL.path
    }
}

struct ParsedMediaName: Equatable, Sendable {
    let title: String
    let season: Int
    let episode: Int
}

enum MediaNameParser {
    private static let patterns = [
        try! NSRegularExpression(pattern: #"(?i)^(.*?)[ ._\-\[]+S(\d{1,3})[ ._\-]*E(\d{1,4})"#),
        try! NSRegularExpression(pattern: #"(?i)^(.*?)[ ._\-\[]+(\d{1,3})x(\d{1,4})"#)
    ]

    static func parse(url: URL) -> ParsedMediaName {
        let raw = url.deletingPathExtension().lastPathComponent
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: raw, range: range), match.numberOfRanges == 4,
                  let titleRange = Range(match.range(at: 1), in: raw),
                  let seasonRange = Range(match.range(at: 2), in: raw),
                  let episodeRange = Range(match.range(at: 3), in: raw)
            else { continue }
            let title = clean(String(raw[titleRange]))
            return ParsedMediaName(
                title: title.isEmpty ? fallbackTitle(for: url) : title,
                season: Int(raw[seasonRange]) ?? 0,
                episode: Int(raw[episodeRange]) ?? 0
            )
        }
        return ParsedMediaName(title: fallbackTitle(for: url), season: 0, episode: 1)
    }

    private static func fallbackTitle(for url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        let parentName = parent.lastPathComponent
        if parentName.range(of: #"(?i)^season[ ._-]*\d+$"#, options: .regularExpression) != nil {
            return clean(parent.deletingLastPathComponent().lastPathComponent)
        }
        if !parentName.isEmpty && parentName != "Movies" { return clean(parentName) }
        return clean(url.deletingPathExtension().lastPathComponent)
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-[]()")))
    }
}

private struct PCDownloadState: Decodable {
    let series: FlexibleID
    let metadata: PCMetadata?
    let completed: [String: PCCompletedRecord]
}

private struct PCMetadata: Decodable {
    let title: String?
    let originalTitle: String?
    let description: String?
    let posterURL: String?
    let inputURL: String?
    let type: String?
    let genres: [String]?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case title, description, type, genres
        case originalTitle = "original_title"
        case posterURL = "poster_url"
        case inputURL = "input_url"
        case updatedAt = "updated_at"
    }
}

private struct PCCompletedRecord: Decodable {
    let season: Int?
    let episode: Int?
    let path: String?
    let bytes: Int64?
    let completedAt: String?
    let title: String?
    let resolution: String?

    enum CodingKeys: String, CodingKey {
        case season, episode, path, bytes, title, resolution
        case completedAt = "completed_at"
    }
}

struct MediaScanResult: Sendable {
    let files: [MediaFile]
    let titles: [OfflineTitle]
}

enum MediaScanner {
    static let supportedExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m2ts"]

    static func scan(sources: [MediaSource], downloadedAssets: [OfflineAssetRecord]) -> MediaScanResult {
        var files: [MediaFile] = []
        var stateTitles: [OfflineTitle] = []
        var pathsOwnedByState = Set<String>()
        var stateFiles: [(url: URL, sourceName: String, sourceRoot: URL)] = []

        for source in sources {
            guard !Task.isCancelled, let root = source.url else { continue }
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard !Task.isCancelled else { break }
                if fileURL.lastPathComponent == ".kinopub-state.json" {
                    stateFiles.append((fileURL, source.name, root))
                    continue
                }
                guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
                guard let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isHidden != true
                else { continue }
                files.append(MediaFile(
                    url: fileURL,
                    byteCount: values.fileSize.map(Int64.init),
                    modifiedAt: values.contentModificationDate,
                    sourceName: source.name
                ))
            }
        }

        for stateFile in stateFiles {
            guard !Task.isCancelled else { break }
            let sourceFiles = files.filter {
                DeviceMediaOwnership.contains($0.url, within: stateFile.sourceRoot)
            }
            if let title = decodePCState(
                at: stateFile.url,
                sourceName: stateFile.sourceName,
                availableFiles: sourceFiles
            ) {
                stateTitles.append(title)
                pathsOwnedByState.formUnion(title.episodes.compactMap { $0.url?.standardizedFileURL.path })
            }
        }

        let genericFiles = files.filter { !pathsOwnedByState.contains($0.url.standardizedFileURL.path) }
        let allTitles = mergeTitles(stateTitles + groupDownloadedAssets(downloadedAssets) + groupGenericFiles(genericFiles))
        return MediaScanResult(
            files: files.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            titles: allTitles.sorted {
                if $0.updatedAt != $1.updatedAt { return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        )
    }

    private static func decodePCState(
        at stateURL: URL,
        sourceName: String,
        availableFiles: [MediaFile]
    ) -> OfflineTitle? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PCDownloadState.self, from: data),
              !state.completed.isEmpty
        else { return nil }

        let directory = stateURL.deletingLastPathComponent()
        let metadata = state.metadata
        let episodes = state.completed.map { key, record -> OfflineEpisode in
            let url = resolvePCAsset(
                path: record.path,
                season: record.season,
                episode: record.episode,
                relativeTo: directory,
                availableFiles: availableFiles
            )
            let fallback = url.map(MediaNameParser.parse)
            let season = record.season ?? fallback?.season ?? 0
            let episode = record.episode ?? fallback?.episode ?? 1
            return OfflineEpisode(
                id: "pc:\(stateURL.path):\(key)",
                url: url,
                season: season,
                episode: episode,
                title: record.title?.nonEmpty ?? fallback?.title ?? "Серия \(episode)",
                byteCount: record.bytes,
                modifiedAt: parseDate(record.completedAt),
                resolution: record.resolution,
                sourceName: sourceName,
                isSystemPlayable: url.map { MediaFile.systemPlayableExtensions.contains($0.pathExtension.lowercased()) } ?? false
            )
        }.sorted(by: episodeSort)

        let catalogID = catalogID(series: state.series.value, inputURL: metadata?.inputURL)
        return OfflineTitle(
            id: catalogID.map { "catalog:\($0)" } ?? "pc:\(stateURL.path)",
            catalogID: catalogID,
            title: metadata?.title?.nonEmpty ?? directory.lastPathComponent,
            originalTitle: metadata?.originalTitle?.nonEmpty,
            summary: metadata?.description?.nonEmpty,
            posterURL: metadata?.posterURL.flatMap(URL.init(string:)),
            type: metadata?.type?.nonEmpty ?? (episodes.contains { $0.season > 0 } ? "serial" : "movie"),
            genres: metadata?.genres ?? [],
            updatedAt: parseDate(metadata?.updatedAt) ?? episodes.compactMap(\.modifiedAt).max(),
            episodes: episodes
        )
    }

    private static func resolvePCAsset(
        path: String?,
        season: Int?,
        episode: Int?,
        relativeTo directory: URL,
        availableFiles: [MediaFile]
    ) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }

        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard let filename = components.last, !filename.isEmpty else { return nil }

        var candidates: [URL] = []
        if normalized.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: normalized))
        } else {
            candidates.append(directory.appendingPathComponent(normalized))
        }
        for length in 1...min(components.count, 5) {
            let suffix = components.suffix(length).joined(separator: "/")
            candidates.append(directory.appendingPathComponent(suffix))
        }

        var seen = Set<String>()
        if let direct = candidates.first(where: { candidate in
            let standardized = candidate.standardizedFileURL
            return seen.insert(standardized.path).inserted &&
                FileManager.default.fileExists(atPath: standardized.path)
        }) {
            return direct.standardizedFileURL
        }

        let filenameMatches = availableFiles.filter {
            $0.url.lastPathComponent.compare(filename, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                DeviceMediaOwnership.contains($0.url, within: directory)
        }
        if filenameMatches.count == 1 {
            return filenameMatches[0].url
        }

        let episodeMatches = filenameMatches.filter { file in
            let parsed = MediaNameParser.parse(url: file.url)
            let seasonMatches = season.map { parsed.season == $0 } ?? true
            let episodeMatches = episode.map { parsed.episode == $0 } ?? true
            return seasonMatches && episodeMatches
        }
        return episodeMatches.count == 1 ? episodeMatches[0].url : nil
    }

    private static func groupGenericFiles(_ files: [MediaFile]) -> [OfflineTitle] {
        Dictionary(grouping: files) { MediaNameParser.parse(url: $0.url).title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            .map { key, grouped in
                let parsed = MediaNameParser.parse(url: grouped[0].url)
                let episodes = grouped.map { file -> OfflineEpisode in
                    let name = MediaNameParser.parse(url: file.url)
                    return OfflineEpisode(
                        id: "file:\(file.url.standardizedFileURL.path)", url: file.url,
                        season: name.season, episode: name.episode, title: file.title,
                        byteCount: file.byteCount, modifiedAt: file.modifiedAt, resolution: nil,
                        sourceName: file.sourceName, isSystemPlayable: file.isSystemPlayable
                    )
                }.sorted(by: episodeSort)
                return OfflineTitle(
                    id: "files:\(key)", catalogID: nil, title: parsed.title, originalTitle: nil,
                    summary: nil, posterURL: nil,
                    type: episodes.contains { $0.season > 0 } ? "serial" : "movie",
                    genres: [], updatedAt: grouped.compactMap(\.modifiedAt).max(), episodes: episodes
                )
            }
    }

    private static func groupDownloadedAssets(_ records: [OfflineAssetRecord]) -> [OfflineTitle] {
        Dictionary(grouping: records, by: \.catalogID).map { catalogID, grouped in
            let first = grouped[0]
            let episodes = grouped.map { record in
                let url = OfflineAssetLocation.resolve(storedPath: record.localURL)
                return OfflineEpisode(
                    id: "download:\(record.id.uuidString)", url: url,
                    season: record.season, episode: record.episode, title: record.episodeTitle,
                    byteCount: nil, modifiedAt: record.downloadedAt, resolution: nil,
                    sourceName: AppDevice.internalStorageName, isSystemPlayable: true
                )
            }.sorted(by: episodeSort)
            return OfflineTitle(
                id: "catalog:\(catalogID)", catalogID: catalogID, title: first.title,
                originalTitle: first.originalTitle, summary: nil,
                posterURL: first.posterURL.flatMap(URL.init(string:)), type: first.type,
                genres: first.genres, updatedAt: grouped.map(\.downloadedAt).max(), episodes: episodes
            )
        }
    }

    private static func mergeTitles(_ titles: [OfflineTitle]) -> [OfflineTitle] {
        let grouped = Dictionary(grouping: titles) { title in
            title.catalogID.map { "catalog:\($0)" } ?? "title:\(title.title.lowercased())"
        }
        return grouped.map { key, matches in
            let richest = matches.max { metadataScore($0) < metadataScore($1) } ?? matches[0]
            let episodes = Dictionary(grouping: matches.flatMap(\.episodes)) {
                "\($0.season):\($0.episode)"
            }
                .compactMap { group in
                    group.value.max { lhs, rhs in
                        let leftScore = (lhs.exists ? 2 : 0) + (lhs.isSystemPlayable ? 1 : 0)
                        let rightScore = (rhs.exists ? 2 : 0) + (rhs.isSystemPlayable ? 1 : 0)
                        return leftScore < rightScore
                    }
                }
                .sorted(by: episodeSort)
            return OfflineTitle(
                id: key, catalogID: richest.catalogID, title: richest.title,
                originalTitle: richest.originalTitle, summary: richest.summary,
                posterURL: richest.posterURL, type: richest.type,
                genres: Array(Set(matches.flatMap(\.genres))).sorted(),
                updatedAt: matches.compactMap(\.updatedAt).max(), episodes: episodes
            )
        }
    }

    private static func metadataScore(_ title: OfflineTitle) -> Int {
        (title.posterURL == nil ? 0 : 4) + (title.catalogID == nil ? 0 : 3) + title.genres.count + (title.summary == nil ? 0 : 1)
    }

    private static func episodeSort(_ lhs: OfflineEpisode, _ rhs: OfflineEpisode) -> Bool {
        if lhs.season != rhs.season { return lhs.season < rhs.season }
        if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func catalogID(series: String, inputURL: String?) -> String? {
        if Int(series) != nil { return series }
        guard let inputURL,
              let regex = try? NSRegularExpression(pattern: #"(?:item|film|serial)[/=:](\d+)"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: inputURL, range: NSRange(inputURL.startIndex..., in: inputURL)),
              let range = Range(match.range(at: 1), in: inputURL)
        else { return nil }
        return String(inputURL[range])
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
