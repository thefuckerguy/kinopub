import SwiftUI
import UIKit

enum AppDevice {
    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    static var platformName: String { isPhone ? "iPhone" : "iPad" }
    static var internalStorageName: String { "На \(platformName)" }
    static var storageSystemImage: String { isPhone ? "iphone" : "ipad" }
}

enum AppBuildInfo {
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "—"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    static var displayVersion: String {
        build.map { "\(version) (\($0))" } ?? version
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case fresh
    case catalog
    case collections
    case watchLater
    case personalViewing
    case watching
    case subscriptions
    case bookmarks
    case history
    case library
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .fresh: "Новинки"
        case .catalog: "Каталог"
        case .collections: "Подборки"
        case .watchLater: "Буду смотреть"
        case .personalViewing: "Персональный просмотр"
        case .watching: "Я смотрю"
        case .subscriptions: "Подписки"
        case .bookmarks: "Закладки"
        case .history: "История"
        case .library: "Офлайн библиотека"
        case .settings: "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh: "flame"
        case .catalog: "movieclapper"
        case .collections: "square.grid.2x2"
        case .watchLater: "eye"
        case .personalViewing: "lock.rectangle.stack"
        case .watching: "play.circle"
        case .subscriptions: "bell.badge"
        case .bookmarks: "bookmark"
        case .history: "clock.arrow.circlepath"
        case .library: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

enum KinoPadTheme {
    static let gold = Color(red: 0.00, green: 0.84, blue: 0.98)
    static let violet = Color(red: 0.49, green: 0.28, blue: 1.00)
    static let canvas = Color(red: 0.012, green: 0.027, blue: 0.075)
    static let sidebar = Color(red: 0.012, green: 0.018, blue: 0.045)
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: KinoPubSession
    @State private var selection: AppSection? = .library

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    BrandHeader()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 14, trailing: 10))
                }

                Section {
                    sidebarLink(.fresh)
                    sidebarLink(.catalog)
                    sidebarLink(.collections)
                }

                Section {
                    sidebarLink(.watchLater)
                    sidebarLink(.personalViewing)
                    sidebarLink(.watching)
                    sidebarLink(.subscriptions)
                    sidebarLink(.bookmarks)
                    sidebarLink(.history)
                }

                Section {
                    sidebarLink(.library)
                    sidebarLink(.settings)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinoPadTheme.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            detail(for: selection ?? .library)
                .background(KinoPadTheme.canvas.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .tint(KinoPadTheme.gold)
        .preferredColorScheme(.dark)
        .task { await session.prepareLoggedInSession() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
                await session.heartbeatCurrentDevice()
            }
        }
    }

    private func sidebarLink(_ section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                .foregroundStyle(selection == section ? KinoPadTheme.gold : .secondary)
                .padding(.vertical, 4)
        }
        .listRowBackground(selection == section ? KinoPadTheme.gold.opacity(0.14) : Color.clear)
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .fresh:
            CatalogView(initialList: .fresh, title: "Новинки")
        case .catalog:
            CatalogView()
        case .collections:
            RemoteLibraryView(section: .collections)
        case .watchLater:
            WatchLaterView()
        case .personalViewing:
            PersonalViewingView()
        case .watching:
            RemoteLibraryView(section: .watching)
        case .subscriptions:
            RemoteLibraryView(section: .subscriptions)
        case .bookmarks:
            RemoteLibraryView(section: .bookmarks)
        case .history:
            RemoteLibraryView(section: .history)
        case .library:
            LibraryView()
        case .settings:
            SettingsView()
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            Image("WooFMascot")
                .resizable().scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(KinoPadTheme.gold.opacity(0.7)))
                .shadow(color: KinoPadTheme.violet.opacity(0.35), radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("WooF.Play").font(.headline)
                Text("кинотеатр на \(AppDevice.platformName)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
