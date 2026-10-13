import AVFAudio
import SwiftUI
import UIKit

@MainActor
final class KinoPadAppDelegate: NSObject, UIApplicationDelegate {
    private static var backgroundCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Self.backgroundCompletionHandler = completionHandler
    }

    static func finishBackgroundEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }
}

@main
struct KinoPadApp: App {
    @UIApplicationDelegateAdaptor(KinoPadAppDelegate.self) private var appDelegate
    @StateObject private var session: KinoPubSession
    @StateObject private var library: MediaLibraryStore
    @StateObject private var progress: PlaybackProgressStore
    @StateObject private var downloads: OfflineDownloadManager
    @StateObject private var watchLater: WatchLaterStore
    @StateObject private var personalViewing: PersonalViewingStore

    init() {
        let library = MediaLibraryStore()
        _session = StateObject(wrappedValue: KinoPubSession())
        _library = StateObject(wrappedValue: library)
        _progress = StateObject(wrappedValue: PlaybackProgressStore())
        _downloads = StateObject(wrappedValue: OfflineDownloadManager(library: library))
        _watchLater = StateObject(wrappedValue: WatchLaterStore())
        _personalViewing = StateObject(wrappedValue: PersonalViewingStore())
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(library)
                .environmentObject(progress)
                .environmentObject(downloads)
                .environmentObject(watchLater)
                .environmentObject(personalViewing)
        }
    }
}
