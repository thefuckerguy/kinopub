import Foundation

struct FlexibleID: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Double.self) {
            self.value = String(format: "%g", value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a string or numeric id")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct FlexibleBool: Codable, Hashable, Sendable {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value != 0
        } else if let value = try? container.decode(String.self) {
            self.value = ["1", "true", "yes"].contains(value.lowercased())
        } else {
            throw DecodingError.typeMismatch(
                Bool.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected a boolean, number or string")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct DeviceChallenge: Equatable, Sendable {
    let code: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int
}

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isUsable: Bool { !accessToken.isEmpty || !refreshToken.isEmpty }
}

struct KinoPubAccount: Equatable, Sendable {
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let subscriptionActive: Bool
    let subscriptionDays: Double
    let subscriptionEnd: Date?
}

struct KinoPubDevice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let hardware: String?
    let software: String?
    let isBrowser: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let lastSeen: Date?

    func isRecentlyActive(at date: Date = Date(), within interval: TimeInterval = 15 * 60) -> Bool {
        guard let lastSeen else { return false }
        let age = date.timeIntervalSince(lastSeen)
        return age >= -60 && age <= interval
    }

    func isSafelyRemovable(at date: Date = Date(), activeWithin interval: TimeInterval = 15 * 60) -> Bool {
        !isBrowser && lastSeen != nil && !isRecentlyActive(at: date, within: interval)
    }
}

struct KinoPubDeviceOverview: Equatable, Sendable {
    static let slotLimit = 5
    static let activityWindow: TimeInterval = 15 * 60

    let devices: [KinoPubDevice]
    let currentDeviceID: String?

    var slotDevices: [KinoPubDevice] { devices.filter { !$0.isBrowser } }
    var browserCount: Int { devices.count - slotDevices.count }

    func activeCount(at date: Date = Date()) -> Int {
        slotDevices.filter { $0.isRecentlyActive(at: date, within: Self.activityWindow) }.count
    }

    var freeSlotCount: Int { max(Self.slotLimit - slotDevices.count, 0) }

    func safelyRemovableCount(at date: Date = Date()) -> Int {
        slotDevices.filter { $0.isSafelyRemovable(at: date, activeWithin: Self.activityWindow) }.count
    }

    func allSlotsRecentlyActive(at date: Date = Date()) -> Bool {
        slotDevices.count >= Self.slotLimit && activeCount(at: date) >= Self.slotLimit
    }
}

struct NamedValue: Codable, Hashable, Sendable {
    let id: FlexibleID?
    let title: String?
}

struct Posters: Codable, Hashable, Sendable {
    let small: String?
    let medium: String?
    let big: String?
    let wide: String?

    var candidateURLs: [URL] {
        var seen = Set<String>()
        return [big, medium, small, wide]
            .compactMap { $0 }
            .flatMap(Self.urls(from:))
            .filter { seen.insert($0.absoluteString).inserted }
    }

    var bestURL: URL? {
        candidateURLs.first
    }

    private static func urls(from rawValue: String) -> [URL] {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }

        if value.hasPrefix("//") {
            return URL(string: "https:\(value)").map { [$0] } ?? []
        }
        guard let url = URL(string: value) else { return [] }

        if url.scheme?.lowercased() == "http" {
            var secure = URLComponents(url: url, resolvingAgainstBaseURL: false)
            secure?.scheme = "https"
            return [secure?.url, url].compactMap { $0 }
        }
        if url.scheme == nil, value.contains(".") {
            return URL(string: "https://\(value)").map { [$0] } ?? []
        }
        return url.scheme == nil ? [] : [url]
    }
}

struct WatchingState: Codable, Hashable, Sendable {
    let status: Int?
    let time: Double?
}

struct StreamURLs: Codable, Hashable, Sendable {
    let http: String?
    let hls: String?
    let hls2: String?
    let hls4: String?

    var bestManifest: URL? {
        [hls4, hls2, hls]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    var directFile: URL? {
        guard let http else { return nil }
        return URL(string: http)
    }
}

struct StreamFile: Codable, Hashable, Sendable {
    let quality: String?
    let codec: String?
    let w: Int?
    let h: Int?
    let url: StreamURLs

    var downloadVariant: DownloadVariant? {
        guard let manifestURL = url.bestManifest else { return nil }
        let resolvedHeight = h ?? Int(quality?.filter(\.isNumber) ?? "")
        let label = resolvedHeight.map { "\($0)p" } ?? quality?.nonEmpty ?? "Авто"
        return DownloadVariant(
            label: label,
            width: w,
            height: resolvedHeight,
            codec: codec,
            manifestURL: manifestURL,
            directFileURL: url.directFile
        )
    }
}

struct DownloadVariant: Identifiable, Hashable, Sendable {
    let label: String
    let width: Int?
    let height: Int?
    let codec: String?
    let manifestURL: URL
    let directFileURL: URL?

    var id: String { manifestURL.absoluteString }

    var displayName: String {
        guard let codec = codec?.nonEmpty else { return label }
        return "\(label) · \(codec.uppercased())"
    }
}

struct CatalogVideo: Codable, Hashable, Sendable {
    let id: FlexibleID?
    let number: Int?
    let title: String?
    let duration: Double?
    let watching: WatchingState?
    let files: [StreamFile]?
    let audios: [CatalogAudio]?
}

struct CatalogEpisode: Codable, Hashable, Sendable {
    let id: FlexibleID?
    let number: Int?
    let title: String?
    let duration: Double?
    let thumbnail: String?
    let watched: Int?
    let watching: WatchingState?
    let files: [StreamFile]?
    let audios: [CatalogAudio]?
}

struct CatalogAudio: Codable, Hashable, Sendable {
    let id: FlexibleID?
    let index: Int?
    let codec: String?
    let lang: String?
    let channels: Int?
    let type: NamedValue?
    let author: NamedValue?

    var displayName: String {
        var parts: [String] = []
        if let author = author?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            parts.append(author)
        }
        if let type = type?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !type.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveCompare(type) == .orderedSame }) {
            parts.append(type)
        }
        if parts.isEmpty, let lang, !lang.isEmpty {
            parts.append(lang.uppercased())
        }
        return parts.isEmpty ? "Аудиодорожка \((index ?? 0) + 1)" : parts.joined(separator: " · ")
    }
}

struct CatalogSeason: Codable, Hashable, Sendable {
    let id: FlexibleID?
    let number: Int?
    let title: String?
    let episodes: [CatalogEpisode]?
}

struct CatalogItem: Codable, Hashable, Identifiable, Sendable {
    let id: FlexibleID
    let type: String?
    let title: String
    let subname: String?
    let year: Int?
    let plot: String?
    let director: String?
    let cast: String?
    let posters: Posters?
    let imdbRating: Double?
    let kinopoiskRating: Double?
    let ratingPercentage: Int?
    let genres: [NamedValue]?
    let countries: [NamedValue]?
    let videos: [CatalogVideo]?
    let seasons: [CatalogSeason]?
    let total: Int?
    let watched: Int?
    let newCount: Int?
    let inWatchlist: FlexibleBool?

    enum CodingKeys: String, CodingKey {
        case id, type, title, subname, year, plot, director, cast, posters, genres, countries, videos, seasons
        case total, watched
        case newCount = "new"
        case inWatchlist = "in_watchlist"
        case imdbRating = "imdb_rating"
        case kinopoiskRating = "kinopoisk_rating"
        case ratingPercentage = "rating_percentage"
    }

    var displayTitle: String {
        if let separator = title.range(of: " / ") {
            return String(title[..<separator.lowerBound])
        }
        return title
    }

    var originalTitle: String? {
        if let subname, !subname.isEmpty { return subname }
        guard let separator = title.range(of: " / ") else { return nil }
        return String(title[separator.upperBound...])
    }

    var ratingText: String? {
        if let kinopoiskRating, kinopoiskRating > 0 {
            return String(format: "КП %.1f", kinopoiskRating)
        }
        if let imdbRating, imdbRating > 0 {
            return String(format: "IMDb %.1f", imdbRating)
        }
        if let ratingPercentage, ratingPercentage > 0 {
            return String(format: "KinoPub %.1f", Double(ratingPercentage) / 10)
        }
        return nil
    }

    var playableItems: [PlayableMedia] {
        if let seasons, !seasons.isEmpty {
            return seasons.flatMap { season in
                (season.episodes ?? []).compactMap { episode in
                    let variants = Self.downloadVariants(in: episode.files ?? [])
                    guard let preferred = variants.first else { return nil }
                    let seasonNumber = season.number ?? 1
                    let episodeNumber = episode.number ?? 1
                    return PlayableMedia(
                        title: episode.title?.nonEmpty ?? "Серия \(episodeNumber)",
                        season: seasonNumber,
                        episode: episodeNumber,
                        duration: episode.duration,
                        resumeTime: episode.watching?.time,
                        isWatched: episode.watched == 1 || episode.watching?.status == 1,
                        audioTracks: episode.audios ?? [],
                        manifestURL: preferred.manifestURL,
                        downloadVariants: variants
                    )
                }
            }
        }

        return (videos ?? []).enumerated().compactMap { index, video in
            let variants = Self.downloadVariants(in: video.files ?? [])
            guard let preferred = variants.first else { return nil }
            return PlayableMedia(
                title: video.title?.nonEmpty ?? displayTitle,
                season: 0,
                episode: video.number ?? index + 1,
                duration: video.duration,
                resumeTime: video.watching?.time,
                isWatched: video.watching?.status == 1,
                audioTracks: video.audios ?? [],
                manifestURL: preferred.manifestURL,
                downloadVariants: variants
            )
        }
    }

    static func bestManifest(in files: [StreamFile]) -> URL? {
        downloadVariants(in: files).first?.manifestURL
    }

    static func downloadVariants(in files: [StreamFile]) -> [DownloadVariant] {
        var seen = Set<String>()
        return files
            .compactMap(\.downloadVariant)
            .filter { seen.insert($0.manifestURL.absoluteString).inserted }
            .sorted { lhs, rhs in
                if (lhs.height ?? 0) != (rhs.height ?? 0) {
                    return (lhs.height ?? 0) > (rhs.height ?? 0)
                }
                let leftIsH264 = lhs.codec?.lowercased().contains("264") == true || lhs.codec?.lowercased().contains("avc") == true
                let rightIsH264 = rhs.codec?.lowercased().contains("264") == true || rhs.codec?.lowercased().contains("avc") == true
                return leftIsH264 && !rightIsH264
            }
    }
}

struct PlayableMedia: Identifiable, Hashable, Sendable {
    let title: String
    let season: Int
    let episode: Int
    let duration: Double?
    let resumeTime: Double?
    let isWatched: Bool
    let audioTracks: [CatalogAudio]
    let manifestURL: URL
    let downloadVariants: [DownloadVariant]

    var id: String { "\(season):\(episode):\(manifestURL.absoluteString)" }
}

struct CatalogPagination: Decodable, Equatable, Sendable {
    let total: Int?
    let current: Int?
    let perpage: Int?
    let totalItems: Int?

    enum CodingKeys: String, CodingKey {
        case total, current, perpage
        case totalItems = "total_items"
    }
}

struct CatalogPage: Decodable, Sendable {
    let items: [CatalogItem]
    let pagination: CatalogPagination?

    func hasPage(after requestedPage: Int, requestedPageSize: Int) -> Bool {
        let current = max(pagination?.current ?? requestedPage, 1)
        if let total = pagination?.total, total > 0 {
            return current < total
        }
        if let totalItems = pagination?.totalItems,
           let perpage = pagination?.perpage,
           perpage > 0 {
            return current * perpage < totalItems
        }
        return items.count >= requestedPageSize
    }
}

struct HistoryPage: Sendable {
    let entries: [HistoryEntry]
    let pagination: CatalogPagination?

    func hasPage(after requestedPage: Int, requestedPageSize: Int) -> Bool {
        let current = max(pagination?.current ?? requestedPage, 1)
        if let total = pagination?.total, total > 0 {
            return current < total
        }
        if let totalItems = pagination?.totalItems,
           let perpage = pagination?.perpage,
           perpage > 0 {
            return current * perpage < totalItems
        }
        return entries.count >= requestedPageSize
    }
}

struct KinoCollection: Decodable, Hashable, Identifiable, Sendable {
    let id: FlexibleID
    let title: String
    let posters: Posters?
}

struct BookmarkFolder: Decodable, Hashable, Identifiable, Sendable {
    let id: FlexibleID
    let title: String
    let count: Int?
}

struct HistoryEntry: Hashable, Identifiable, Sendable {
    let item: CatalogItem
    let lastSeen: Date?
    let season: Int
    let episode: Int

    var id: String { "\(item.id.value):\(season):\(episode):\(lastSeen?.timeIntervalSince1970 ?? 0)" }
}

private extension StreamFile {
    var isH264: Bool {
        let value = codec?.lowercased() ?? ""
        return value.contains("264") || value.contains("avc")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
