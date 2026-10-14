import AVKit
import MediaPlayer
import SwiftUI
import UIKit

struct VideoPlayerScreen: View {
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
    @State private var controlsTimeObserver: Any?
    @State private var lastRemoteSync = Date.distantPast
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var selectedAudioIndex: Int?
    @State private var hasStarted = false
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var playbackPosition: Double = 0
    @State private var playbackDuration: Double = 0
    @State private var seekPosition: Double = 0
    @State private var isSeeking = false

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
            PlayerSurface(player: player)
                .ignoresSafeArea()
                .accessibilityLabel(title)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleControls)

            if controlsVisible {
                VStack(spacing: 0) {
                    HStack {
                        if let onClose {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .frame(width: 40, height: 40)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .accessibilityLabel("Закрыть")
                        }
                        Spacer()
                        audioMenu
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer()

                    playbackControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            startPlayback()
            showControlsTemporarily()
        }
        .onDisappear(perform: stopPlayback)
        .persistentSystemOverlays(.hidden)
    }

    private var playbackControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 38) {
                Button {
                    seek(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 30, weight: .regular))
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel("Назад на 15 секунд")

                Button {
                    if player.timeControlStatus == .playing {
                        player.pause()
                    } else {
                        player.play()
                    }
                    showControlsTemporarily()
                } label: {
                    Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(player.timeControlStatus == .playing ? "Пауза" : "Воспроизвести")

                Button {
                    seek(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 30, weight: .regular))
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel("Вперёд на 15 секунд")
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(timeLabel(isSeeking ? seekPosition : playbackPosition))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                Slider(value: Binding(
                    get: { isSeeking ? seekPosition : playbackPosition },
                    set: { seekPosition = $0 }
                ), in: 0...max(playbackDuration, 1), onEditingChanged: { editing in
                    isSeeking = editing
                    if editing {
                        controlsHideTask?.cancel()
                    } else {
                        performSeek(to: seekPosition)
                        showControlsTemporarily()
                    }
                })
                .tint(.white)
                .accessibilityLabel("Перемотка")
                Text(timeLabel(playbackDuration))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
            .font(.caption)

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                SystemVolumeSlider()
                    .frame(width: 150, height: 28)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Громкость устройства")
        }
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func timeLabel(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let seconds = Int(time)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func seek(by offset: Double) {
        performSeek(to: min(max(player.currentTime().seconds + offset, 0), max(playbackDuration, 0)))
        showControlsTemporarily()
    }

    private func performSeek(to position: Double) {
        let target = min(max(position, 0), max(playbackDuration, 0))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        playbackPosition = target
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
                Image(systemName: "speaker.wave.2.fill")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Выбрать озвучку: \(selectedAudioLabel)")
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
        controlsTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { currentTime in
            Task { @MainActor in
                if !isSeeking { playbackPosition = currentTime.seconds.isFinite ? currentTime.seconds : 0 }
                let duration = player.currentItem?.duration.seconds ?? 0
                playbackDuration = duration.isFinite && duration > 0 ? duration : 0
            }
        }
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
        controlsHideTask?.cancel()
        controlsHideTask = nil
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
        if let controlsTimeObserver {
            player.removeTimeObserver(controlsTimeObserver)
            self.controlsTimeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        audioGroup = nil
        audioOptions = []
        selectedAudioIndex = nil
    }

    private func toggleControls() {
        if controlsVisible {
            controlsHideTask?.cancel()
            withAnimation(.easeOut(duration: 0.2)) {
                controlsVisible = false
            }
        } else {
            showControlsTemporarily()
        }
    }

    private func showControlsTemporarily() {
        controlsHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            controlsVisible = true
        }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
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

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: PlayerSurfaceView, coordinator: Void) {
        uiView.player = nil
    }
}

private final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.videoGravity = .resizeAspect
            playerLayer.player = newValue
        }
    }
}
