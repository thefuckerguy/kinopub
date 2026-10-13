import Foundation

struct PlaybackRecord: Codable, Equatable, Sendable {
    var position: Double
    var duration: Double
    var isWatched: Bool
    var updatedAt: Date

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

struct PlaybackContext: Equatable, Sendable {
    let key: String
    let catalogID: String?
    let season: Int
    let episode: Int
    let initialPosition: Double?
    let initialDuration: Double?

    static func online(catalogID: String, media: PlayableMedia) -> PlaybackContext {
        PlaybackContext(
            key: "online:\(catalogID):\(media.season):\(media.episode)",
            catalogID: catalogID,
            season: media.season,
            episode: media.episode,
            initialPosition: media.resumeTime,
            initialDuration: media.duration
        )
    }

    static func offline(_ episode: OfflineEpisode, catalogID: String?) -> PlaybackContext {
        PlaybackContext(
            key: episode.progressKey,
            catalogID: catalogID,
            season: episode.season,
            episode: episode.episode,
            initialPosition: nil,
            initialDuration: nil
        )
    }
}

@MainActor
final class PlaybackProgressStore: ObservableObject {
    @Published private(set) var records: [String: PlaybackRecord]

    private let defaults: UserDefaults
    private let storageKey = "playbackProgress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: PlaybackRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func record(for key: String) -> PlaybackRecord? { records[key] }
    func isWatched(_ key: String) -> Bool { records[key]?.isWatched == true }

    func resumePosition(for context: PlaybackContext) -> Double {
        max(records[context.key]?.position ?? 0, context.initialPosition ?? 0)
    }

    func update(key: String, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 0 else { return }
        let resolvedDuration = duration > 0 ? duration : (records[key]?.duration ?? 0)
        let watched = records[key]?.isWatched == true || Self.shouldAutomaticallyMarkWatched(
            position: position,
            duration: resolvedDuration
        )
        records[key] = PlaybackRecord(
            position: max(position, 0),
            duration: max(resolvedDuration, 0),
            isWatched: watched,
            updatedAt: Date()
        )
        persist()
    }

    func setWatched(_ watched: Bool, key: String, duration: Double? = nil) {
        let current = records[key]
        let resolvedDuration = max(duration ?? current?.duration ?? 0, 0)
        records[key] = PlaybackRecord(
            position: watched && resolvedDuration > 0 ? resolvedDuration : (current?.position ?? 0),
            duration: resolvedDuration,
            isWatched: watched,
            updatedAt: Date()
        )
        persist()
    }

    nonisolated static func shouldAutomaticallyMarkWatched(position: Double, duration: Double) -> Bool {
        guard duration >= 60, position >= 0 else { return false }
        return position / duration >= 0.9 || (duration >= 600 && duration - position <= 120)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
