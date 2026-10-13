import Foundation
import UIKit

enum CatalogList: String, CaseIterable, Identifiable {
    case popular
    case hot
    case fresh

    var id: Self { self }

    var title: String {
        switch self {
        case .popular: "Популярное"
        case .hot: "Горячее"
        case .fresh: "Новинки"
        }
    }
}

enum KinoPubDeviceManagementError: LocalizedError {
    case currentDevice
    case activeDevice
    case browserDevice
    case unknownActivity
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .currentDevice: "Текущее устройство нельзя отвязать из WooF.Play."
        case .activeDevice: "Устройство активно в последние 15 минут и не может быть отвязано."
        case .browserDevice: "Браузер не занимает слот устройства и не отвязывается из WooF.Play."
        case .unknownActivity: "KinoPub не сообщил время последней активности. Безопасная отвязка запрещена."
        case .deviceNotFound: "Устройство больше не найдено в аккаунте. Обновите список."
        }
    }
}

@MainActor
final class KinoPubSession: ObservableObject {
    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var challenge: DeviceChallenge?
    @Published private(set) var isSigningIn = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var currentPage = 0
    @Published private(set) var totalPages: Int?
    @Published private(set) var canLoadMore = false
    @Published private(set) var subscriptionOverrides: [String: Bool] = [:]
    @Published private(set) var updatingSubscriptions: Set<String> = []
    @Published private(set) var account: KinoPubAccount?
    @Published private(set) var isLoadingAccount = false
    @Published private(set) var isUpdatingDevice = false
    @Published private(set) var deviceDisplayName: String
    @Published private(set) var deviceOverview: KinoPubDeviceOverview?
    @Published private(set) var isLoadingDevices = false
    @Published var deviceManagementError: String?
    @Published var errorMessage: String?
    @Published var selectedList: CatalogList = .popular

    private let api: KinoPubAPI
    private let defaults: UserDefaults
    private var loginTask: Task<Void, Never>?
    private var activeSearchQuery: String?
    private var activeList: CatalogList = .popular
    private var catalogRequestID = UUID()
    private let catalogPageSize = 40

    init(defaults: UserDefaults = .standard) {
        let storedTokens = TokenStore.load()
        self.defaults = defaults
        api = KinoPubAPI(tokens: storedTokens)
        isLoggedIn = storedTokens?.isUsable == true
        let savedName = defaults.string(forKey: "kinoWatchDeviceDisplayName")
        deviceDisplayName = savedName.flatMap { $0.isEmpty ? nil : $0 } ?? UIDevice.current.name
    }

    func prepareLoggedInSession() async {
        guard isLoggedIn else { return }
        await notifyCurrentDevice()
        await refreshAccount()
        await refreshDevices()
    }

    func refreshAccount() async {
        guard isLoggedIn, !isLoadingAccount else { return }
        isLoadingAccount = true
        defer { isLoadingAccount = false }
        do {
            account = try await api.account()
        } catch {
            handle(error)
        }
    }

    func updateDeviceDisplayName(_ value: String) async {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        deviceDisplayName = normalized
        defaults.set(normalized, forKey: "kinoWatchDeviceDisplayName")
        await notifyCurrentDevice()
    }

    private func notifyCurrentDevice() async {
        guard isLoggedIn, !isUpdatingDevice else { return }
        isUpdatingDevice = true
        defer { isUpdatingDevice = false }
        do {
            try await sendDeviceIdentity()
        } catch {
            handle(error)
        }
    }

    func heartbeatCurrentDevice() async {
        guard isLoggedIn else { return }
        do {
            try await sendDeviceIdentity()
        } catch KinoPubAPIError.notAuthenticated {
            handle(KinoPubAPIError.notAuthenticated)
        } catch {
            // A background heartbeat must not interrupt playback or browsing.
        }
    }

    func refreshDevices() async {
        guard isLoggedIn, !isLoadingDevices else { return }
        isLoadingDevices = true
        deviceManagementError = nil
        defer { isLoadingDevices = false }
        do {
            deviceOverview = try await api.deviceOverview()
        } catch {
            deviceManagementError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeDevice(_ device: KinoPubDevice) async {
        guard isLoggedIn, !isLoadingDevices else { return }
        isLoadingDevices = true
        deviceManagementError = nil
        defer { isLoadingDevices = false }
        do {
            let latest = try await api.deviceOverview()
            guard let latestDevice = latest.devices.first(where: { $0.id == device.id }) else {
                deviceOverview = latest
                throw KinoPubDeviceManagementError.deviceNotFound
            }
            guard latest.currentDeviceID != latestDevice.id else {
                deviceOverview = latest
                throw KinoPubDeviceManagementError.currentDevice
            }
            guard !latestDevice.isBrowser else {
                deviceOverview = latest
                throw KinoPubDeviceManagementError.browserDevice
            }
            guard latestDevice.lastSeen != nil else {
                deviceOverview = latest
                throw KinoPubDeviceManagementError.unknownActivity
            }
            guard latestDevice.isSafelyRemovable(activeWithin: KinoPubDeviceOverview.activityWindow) else {
                deviceOverview = latest
                throw KinoPubDeviceManagementError.activeDevice
            }
            try await api.removeDevice(id: latestDevice.id)
            deviceOverview = try await api.deviceOverview()
        } catch {
            deviceManagementError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendDeviceIdentity() async throws {
        let device = UIDevice.current
        try await api.notifyDevice(
            title: "WooF.Play · \(deviceDisplayName)",
            hardware: "\(device.model) · \(device.name) · \(device.systemName) \(device.systemVersion)",
            software: "WooF.Play 0.3.6"
        )
    }

    func loadCatalog() async {
        guard isLoggedIn else { return }
        let requestID = UUID()
        catalogRequestID = requestID
        activeSearchQuery = nil
        activeList = selectedList
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if catalogRequestID == requestID { isLoading = false }
        }
        do {
            let page = try await api.top(
                kind: activeList.rawValue,
                page: 1,
                perPage: catalogPageSize
            )
            guard catalogRequestID == requestID else { return }
            applyFirstPage(page, requestedPage: 1)
        } catch {
            guard catalogRequestID == requestID else { return }
            handle(error)
        }
    }

    func search(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            await loadCatalog()
            return
        }
        let requestID = UUID()
        catalogRequestID = requestID
        activeSearchQuery = normalized
        activeList = selectedList
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if catalogRequestID == requestID { isLoading = false }
        }
        do {
            let page = try await api.search(normalized, page: 1, perPage: catalogPageSize)
            guard catalogRequestID == requestID else { return }
            applyFirstPage(page, requestedPage: 1)
        } catch {
            guard catalogRequestID == requestID else { return }
            handle(error)
        }
    }

    func reloadCurrentCatalog() async {
        if let activeSearchQuery {
            await search(activeSearchQuery)
        } else {
            await loadCatalog()
        }
    }

    func loadNextCatalogPage() async {
        guard isLoggedIn, !isLoading, !isLoadingMore, canLoadMore else { return }
        let requestID = catalogRequestID
        let requestedPage = max(currentPage + 1, 2)
        let query = activeSearchQuery
        let list = activeList
        isLoadingMore = true
        errorMessage = nil
        defer {
            if catalogRequestID == requestID { isLoadingMore = false }
        }

        do {
            let page: CatalogPage
            if let query {
                page = try await api.search(query, page: requestedPage, perPage: catalogPageSize)
            } else {
                page = try await api.top(
                    kind: list.rawValue,
                    page: requestedPage,
                    perPage: catalogPageSize
                )
            }
            guard catalogRequestID == requestID else { return }
            items = mergingCatalogItems(items, page.items)
            updatePagination(from: page, requestedPage: requestedPage)
        } catch {
            guard catalogRequestID == requestID else { return }
            handle(error)
        }
    }

    func details(for id: String) async throws -> CatalogItem {
        try await api.item(id: id)
    }

    func collections(page: Int = 1) async throws -> [KinoCollection] { try await api.collections(page: page) }
    func collectionItems(id: String, page: Int = 1) async throws -> CatalogPage {
        try await api.collectionItems(id: id, page: page)
    }
    func bookmarks() async throws -> [BookmarkFolder] { try await api.bookmarks() }
    func bookmarkItems(id: String, page: Int = 1) async throws -> CatalogPage {
        try await api.bookmarkItems(id: id, page: page)
    }
    func bookmarkFolders(for itemID: String) async throws -> [BookmarkFolder] {
        try await api.bookmarkFolders(itemID: itemID)
    }
    func createBookmarkFolder(title: String) async throws {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw KinoPubAPIError.invalidResponse }
        try await api.createBookmarkFolder(title: normalized)
    }
    func removeBookmarkFolder(id: String) async throws {
        try await api.removeBookmarkFolder(id: id)
    }
    func setBookmarkMembership(itemID: String, folderID: String, isMember: Bool) async throws {
        if isMember {
            try await api.addBookmarkItem(itemID: itemID, folderID: folderID)
        } else {
            try await api.removeBookmarkItem(itemID: itemID, folderID: folderID)
        }
    }
    func watching(type: String = "serials", subscribed: Bool = false, page: Int = 1) async throws -> CatalogPage {
        try await api.watching(type: type, subscribed: subscribed, page: page)
    }
    func history(page: Int = 1) async throws -> HistoryPage { try await api.history(page: page) }

    func isSubscribed(_ item: CatalogItem) -> Bool {
        subscriptionOverrides[item.id.value] ?? item.inWatchlist?.value ?? false
    }

    func isUpdatingSubscription(_ itemID: String) -> Bool {
        updatingSubscriptions.contains(itemID)
    }

    func rememberSubscriptionItems(_ items: [CatalogItem]) {
        for item in items {
            subscriptionOverrides[item.id.value] = true
        }
    }

    @discardableResult
    func toggleSubscription(for item: CatalogItem) async throws -> Bool {
        let id = item.id.value
        guard !updatingSubscriptions.contains(id) else { return isSubscribed(item) }
        updatingSubscriptions.insert(id)
        defer { updatingSubscriptions.remove(id) }
        let isSubscribed = try await api.toggleSubscription(id: id)
        subscriptionOverrides[id] = isSubscribed
        return isSubscribed
    }

    func markTime(catalogID: String, season: Int, episode: Int, seconds: Double) async {
        guard isLoggedIn, seconds.isFinite else { return }
        do {
            try await api.markTime(
                id: catalogID,
                season: season,
                episode: episode,
                seconds: Int(max(seconds, 0))
            )
        } catch KinoPubAPIError.notAuthenticated {
            TokenStore.clear()
            isLoggedIn = false
        } catch {
            // Playback must not be interrupted if progress sync is temporarily unavailable.
        }
    }

    func startLogin() {
        guard loginTask == nil else { return }
        isSigningIn = true
        errorMessage = nil

        loginTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isSigningIn = false
                loginTask = nil
            }
            do {
                let pendingChallenge = try await api.requestDeviceCode()
                challenge = pendingChallenge
                let deadline = Date().addingTimeInterval(TimeInterval(pendingChallenge.expiresIn))

                while !Task.isCancelled, Date() < deadline {
                    do {
                        _ = try await api.pollDeviceToken(code: pendingChallenge.code)
                        isLoggedIn = true
                        challenge = nil
                        await prepareLoggedInSession()
                        await loadCatalog()
                        return
                    } catch KinoPubAPIError.authorizationPending {
                        try await Task.sleep(for: .seconds(pendingChallenge.interval))
                    }
                }
                if !Task.isCancelled {
                    errorMessage = "Срок действия кода истёк. Получите новый код."
                }
            } catch is CancellationError {
                // User canceled the flow.
            } catch {
                handle(error)
            }
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        challenge = nil
        isSigningIn = false
    }

    func logOut() {
        cancelLogin()
        TokenStore.clear()
        isLoggedIn = false
        account = nil
        deviceOverview = nil
        deviceManagementError = nil
        items = []
        currentPage = 0
        totalPages = nil
        canLoadMore = false
        subscriptionOverrides = [:]
        updatingSubscriptions = []
        activeSearchQuery = nil
        catalogRequestID = UUID()
        Task { await api.setTokens(nil) }
    }

    private func applyFirstPage(_ page: CatalogPage, requestedPage: Int) {
        items = mergingCatalogItems([], page.items)
        updatePagination(from: page, requestedPage: requestedPage)
    }

    private func updatePagination(from page: CatalogPage, requestedPage: Int) {
        currentPage = max(page.pagination?.current ?? requestedPage, 1)
        totalPages = page.pagination?.total
        canLoadMore = page.hasPage(after: requestedPage, requestedPageSize: catalogPageSize)
    }

    private func handle(_ error: Error) {
        if case KinoPubAPIError.notAuthenticated = error {
            TokenStore.clear()
            isLoggedIn = false
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

func mergingCatalogItems(_ existing: [CatalogItem], _ additions: [CatalogItem]) -> [CatalogItem] {
    var seen = Set(existing.map(\.id.value))
    return existing + additions.filter { seen.insert($0.id.value).inserted }
}
