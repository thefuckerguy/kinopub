import AVKit
import SwiftUI

struct VideoPlayerScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var progressStore: PlaybackProgressStore
    @EnvironmentObject private var session: KinoPubSession

    let url: URL
    let title: String
    let compatibilityWarning: String?
    let context: PlaybackContext?
    let audioTracks: [CatalogAudio]
    let onClose: (() -> Void)?

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?
    @State private var lastRemoteSync = Date.distantPast
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var selectedAudioIndex: Int?
    @State private var hasStarted = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    init(
        url: URL,
        title: String,
        compatibilityWarning: String?,
        context: PlaybackContext? = nil,
        audioTracks: [CatalogAudio] = [],
        onClose: (() -> Void)? = nil
    ) {
        self.url = url
        self.title = title
        self.compatibilityWarning = compatibilityWarning
        self.context = context
        self.audioTracks = audioTracks
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if let onClose {
                        Button(action: onClose) {
                            if isCompact {
                                Image(systemName: "xmark.circle.fill")
                            } else {
                                Label("Закрыть", systemImage: "xmark.circle.fill")
                            }
                        }
                        .accessibilityLabel("Закрыть")
                    }
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.black.opacity(0.72), in: Capsule())
                    Spacer()
                    audioMenu
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.72))
                .padding()

                Spacer()

                if let compatibilityWarning {
                    Label(compatibilityWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.8))
                }
            }
        }
        .onAppear(perform: startPlayback)
        .onDisappear(perform: stopPlayback)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private var audioMenu: some View {
        if !audioOptions.isEmpty {
            Menu {
                ForEach(Array(audioOptions.enumerated()), id: \.offset) { index, _ in
                    Button {
                        selectAudio(at: index)
                    } label: {
                        if selectedAudioIndex == index {
                            Label(audioLabel(at: index), systemImage: "checkmark")
                        } else {
                            Text(audioLabel(at: index))
                        }
                    }
                }
            } label: {
                if isCompact {
                    Image(systemName: "speaker.wave.2.fill")
                } else {
                    Label(selectedAudioLabel, systemImage: "speaker.wave.2.fill")
                        .lineLimit(1)
                }
            }
            .accessibilityLabel("Выбрать озвучку")
        } else if !audioTracks.isEmpty {
            if isCompact {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(height: 38)
                    .accessibilityLabel("Озвучки")
            } else {
                Label("Озвучки", systemImage: "speaker.wave.2.fill")
                    .frame(height: 38)
            }
        }
    }

    private var selectedAudioLabel: String {
        guard let selectedAudioIndex else { return "Озвучка" }
        return audioLabel(at: selectedAudioIndex)
    }

    private func startPlayback() {
        guard !hasStarted else { return }
        hasStarted = true
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        loadAudioOptions(for: item)
        if let context {
            let resume = progressStore.resumePosition(for: context)
            if resume > 5 {
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { currentTime in
            Task { @MainActor in
                guard let context else { return }
                let position = currentTime.seconds
                let itemDuration = player.currentItem?.duration.seconds ?? 0
                let duration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : (context.initialDuration ?? 0)
                progressStore.update(key: context.key, position: position, duration: duration)

                if let catalogID = context.catalogID, Date().timeIntervalSince(lastRemoteSync) >= 30 {
                    lastRemoteSync = Date()
                    await session.markTime(
                        catalogID: catalogID,
                        season: context.season,
                        episode: context.episode,
                        seconds: position
                    )
                }
            }
        }
        player.play()
    }

    private func stopPlayback() {
        guard hasStarted else { return }
        hasStarted = false
        let position = player.currentTime().seconds
        if let context {
            let itemDuration = player.currentItem?.duration.seconds ?? 0
            let duration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : (context.initialDuration ?? 0)
            progressStore.update(key: context.key, position: position, duration: duration)
            if let catalogID = context.catalogID {
                Task {
                    await session.markTime(
                        catalogID: catalogID,
                        season: context.season,
                        episode: context.episode,
                        seconds: position
                    )
                }
            }
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        audioGroup = nil
        audioOptions = []
        selectedAudioIndex = nil
    }

    private func loadAudioOptions(for item: AVPlayerItem) {
        Task { @MainActor in
            do {
                let group = try await item.asset.loadMediaSelectionGroup(for: .audible)
                guard player.currentItem === item, let group else { return }
                audioGroup = group
                audioOptions = group.options
                if let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                    selectedAudioIndex = group.options.firstIndex(where: { $0 === selected })
                } else if !group.options.isEmpty {
                    selectedAudioIndex = 0
                }
            } catch {
                // The native player may still expose audio controls if the HLS manifest loads later.
            }
        }
    }

    private func selectAudio(at index: Int) {
        guard audioOptions.indices.contains(index), let audioGroup, let item = player.currentItem else { return }
        player.appliesMediaSelectionCriteriaAutomatically = false
        item.select(audioOptions[index], in: audioGroup)
        selectedAudioIndex = index
    }

    private func audioLabel(at index: Int) -> String {
        let orderedTracks = audioTracks.sorted {
            ($0.index ?? Int.max) < ($1.index ?? Int.max)
        }
        if orderedTracks.indices.contains(index) {
            return orderedTracks[index].displayName
        }
        if audioOptions.indices.contains(index) {
            return audioOptions[index].displayName
        }
        return "Аудиодорожка \(index + 1)"
    }
}
