import Foundation

enum KinoPubAPIError: LocalizedError, Equatable {
    case authorizationPending
    case authorizationFailed(String)
    case notAuthenticated
    case invalidResponse
    case server(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .authorizationPending:
            "Ожидаю подтверждения кода"
        case .authorizationFailed(let message):
            "Авторизация отклонена: \(message)"
        case .notAuthenticated:
            "Требуется вход в kino.watch"
        case .invalidResponse:
            "Сервер вернул некорректный ответ"
        case .server(let code, let message):
            "Ошибка сервера \(code): \(message)"
        case .decoding(let message):
            "Не удалось прочитать ответ: \(message)"
        }
    }
}

private enum KinoPubConfiguration {
    static let baseURL = URL(string: "https://api.service-kp.com")!
    static let clientID = "xbmc"
    // Public compatibility credential used by the existing fork and other TV clients.
    static let clientSecret = "cgg3gtifu46urtfp2zp1nqtba0k2ezxh"
}

private struct DeviceCodeResponse: Decodable {
    let code: String?
    let userCode: String?
    let verificationURI: String?
    let expiresIn: Int?
    let interval: Int?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case code, error, interval
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case errorDescription = "error_description"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case errorDescription = "error_description"
    }
}

private struct ItemResponse: Decodable {
    let item: CatalogItem
}

private struct ItemsResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
}

private struct BookmarkFoldersResponse: Decodable {
    let folders: [BookmarkFolder]
}

private struct HistoryResponse: Decodable {
    let items: [CatalogItem]?
    let history: [HistoryWrapper]?
    let pagination: CatalogPagination?
}

private struct HistoryWrapper: Decodable {
    let item: CatalogItem
    let lastSeen: Double?
    let media: HistoryMedia?

    enum CodingKeys: String, CodingKey {
        case item, media
        case lastSeen = "last_seen"
    }
}

private struct HistoryMedia: Decodable {
    let number: Int?
    let seasonNumber: Int?

    enum CodingKeys: String, CodingKey {
        case number
        case seasonNumber = "snumber"
    }
}

private struct UserResponse: Decodable {
    let user: UserPayload
}

private struct UserPayload: Decodable {
    let username: String
    let subscription: SubscriptionPayload?
    let profile: ProfilePayload?
}

private struct SubscriptionPayload: Decodable {
    let active: Bool?
    let endTime: Double?
    let days: Double?

    enum CodingKeys: String, CodingKey {
        case active, days
        case endTime = "end_time"
    }
}

private struct ProfilePayload: Decodable {
    let name: String?
    let avatar: String?
}

private struct IgnoredResponse: Decodable {}

private struct DevicePayload: Decodable {
    let id: FlexibleID
    let title: String?
    let hardware: String?
    let software: String?
    let isBrowser: FlexibleBool?
    let created: Double?
    let updated: Double?
    let lastSeen: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, hardware, software, created, updated
        case isBrowser = "is_browser"
        case lastSeen = "last_seen"
    }

    var model: KinoPubDevice {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return KinoPubDevice(
            id: id.value,
            title: normalizedTitle?.isEmpty == false ? normalizedTitle! : "Устройство \(id.value)",
            hardware: hardware,
            software: software,
            isBrowser: isBrowser?.value ?? false,
            createdAt: created.map(Date.init(timeIntervalSince1970:)),
            updatedAt: updated.map(Date.init(timeIntervalSince1970:)),
            lastSeen: lastSeen.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct DevicesResponse: Decodable {
    let devices: [DevicePayload]
}

private struct DeviceInfoResponse: Decodable {
    let device: DevicePayload
}

private struct DeviceRemovalResponse: Decodable {
    let current: FlexibleBool?
}

actor KinoPubAPI {
    private let session: URLSession
    private var tokens: AuthTokens?

    init(tokens: AuthTokens?) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        self.tokens = tokens
    }

    func setTokens(_ tokens: AuthTokens?) {
        self.tokens = tokens
    }

    func requestDeviceCode() async throws -> DeviceChallenge {
        let response: DeviceCodeResponse = try await oauth([
            "grant_type": "device_code",
            "client_id": KinoPubConfiguration.clientID,
            "client_secret": KinoPubConfiguration.clientSecret
        ])
        if let error = response.error {
            throw KinoPubAPIError.authorizationFailed(response.errorDescription ?? error)
        }
        guard let code = response.code,
              let userCode = response.userCode,
              let verificationURL = URL(string: response.verificationURI ?? "https://kino.watch/device")
        else { throw KinoPubAPIError.invalidResponse }

        return DeviceChallenge(
            code: code,
            userCode: userCode,
            verificationURL: verificationURL,
            expiresIn: response.expiresIn ?? 600,
            interval: max(response.interval ?? 5, 2)
        )
    }

    func pollDeviceToken(code: String) async throws -> AuthTokens {
        let response: TokenResponse = try await oauth([
            "grant_type": "device_token",
            "client_id": KinoPubConfiguration.clientID,
            "client_secret": KinoPubConfiguration.clientSecret,
            "code": code
        ])
        if response.error == "authorization_pending" || response.error == "slow_down" {
            throw KinoPubAPIError.authorizationPending
        }
        if let error = response.error {
            throw KinoPubAPIError.authorizationFailed(response.errorDescription ?? error)
        }
        let updated = try makeTokens(from: response, fallbackRefreshToken: nil)
        tokens = updated
        try TokenStore.save(updated)
        return updated
    }

    func top(
        kind: String = "popular",
        type: String = "movie,serial",
        page: Int = 1,
        perPage: Int = 40
    ) async throws -> CatalogPage {
        try await get(
            path: "items/\(kind)",
            query: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "perpage", value: String(max(perPage, 1)))
            ]
        )
    }

    func search(_ query: String, page: Int = 1, perPage: Int = 40) async throws -> CatalogPage {
        try await get(
            path: "items/search",
            query: [
                URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "field", value: "title"),
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "perpage", value: String(max(perPage, 1)))
            ]
        )
    }

    func item(id: String) async throws -> CatalogItem {
        let response: ItemResponse = try await get(path: "items/\(id)", query: [])
        return response.item
    }

    func collections(sort: String = "created-", page: Int = 1) async throws -> [KinoCollection] {
        let response: ItemsResponse<KinoCollection> = try await get(
            path: "collections",
            query: [
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "page", value: String(max(page, 1)))
            ]
        )
        return response.items
    }

    func collectionItems(id: String, page: Int = 1) async throws -> CatalogPage {
        try await get(
            path: "collections/view",
            query: [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "page", value: String(max(page, 1)))
            ]
        )
    }

    func bookmarks() async throws -> [BookmarkFolder] {
        let response: ItemsResponse<BookmarkFolder> = try await get(path: "bookmarks", query: [])
        return response.items
    }

    func bookmarkItems(id: String, page: Int = 1) async throws -> CatalogPage {
        try await get(
            path: "bookmarks/\(id)",
            query: [URLQueryItem(name: "page", value: String(max(page, 1)))]
        )
    }

    func bookmarkFolders(itemID: String) async throws -> [BookmarkFolder] {
        let response: BookmarkFoldersResponse = try await get(
            path: "bookmarks/get-item-folders",
            query: [URLQueryItem(name: "item", value: itemID)]
        )
        return response.folders
    }

    func createBookmarkFolder(title: String) async throws {
        let _: IgnoredResponse = try await post(
            path: "bookmarks/create",
            query: [URLQueryItem(name: "title", value: title)]
        )
    }

    func removeBookmarkFolder(id: String) async throws {
        let _: IgnoredResponse = try await post(
            path: "bookmarks/remove-folder",
            query: [URLQueryItem(name: "folder", value: id)]
        )
    }

    func addBookmarkItem(itemID: String, folderID: String) async throws {
        let _: IgnoredResponse = try await post(
            path: "bookmarks/add",
            query: [
                URLQueryItem(name: "item", value: itemID),
                URLQueryItem(name: "folder", value: folderID)
            ]
        )
    }

    func removeBookmarkItem(itemID: String, folderID: String) async throws {
        let _: IgnoredResponse = try await post(
            path: "bookmarks/remove-item",
            query: [
                URLQueryItem(name: "item", value: itemID),
                URLQueryItem(name: "folder", value: folderID)
            ]
        )
    }

    func watching(type: String = "serials", subscribed: Bool = false, page: Int = 1) async throws -> CatalogPage {
        var query = [URLQueryItem(name: "page", value: String(max(page, 1)))]
        if subscribed {
            query.append(URLQueryItem(name: "subscribed", value: "1"))
        }
        return try await get(
            path: "watching/\(type)",
            query: query
        )
    }

    func history(page: Int = 1) async throws -> HistoryPage {
        let response: HistoryResponse = try await get(
            path: "history",
            query: [URLQueryItem(name: "page", value: String(max(page, 1)))]
        )
        if let wrapped = response.history, !wrapped.isEmpty {
            return HistoryPage(
                entries: wrapped.map {
                    HistoryEntry(
                        item: $0.item,
                        lastSeen: $0.lastSeen.map(Date.init(timeIntervalSince1970:)),
                        season: $0.media?.seasonNumber ?? 0,
                        episode: $0.media?.number ?? 0
                    )
                },
                pagination: response.pagination
            )
        }
        return HistoryPage(
            entries: (response.items ?? []).map {
                HistoryEntry(item: $0, lastSeen: nil, season: 0, episode: 0)
            },
            pagination: response.pagination
        )
    }

    func account() async throws -> KinoPubAccount {
        let response: UserResponse = try await get(path: "user", query: [])
        return KinoPubAccount(
            username: response.user.username,
            displayName: response.user.profile?.name.flatMap { $0.isEmpty ? nil : $0 },
            avatarURL: response.user.profile?.avatar.flatMap(URL.init(string:)),
            subscriptionActive: response.user.subscription?.active ?? false,
            subscriptionDays: response.user.subscription?.days ?? 0,
            subscriptionEnd: response.user.subscription?.endTime.map(Date.init(timeIntervalSince1970:))
        )
    }

    func notifyDevice(title: String, hardware: String, software: String) async throws {
        let _: IgnoredResponse = try await post(
            path: "device/notify",
            query: [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "hardware", value: hardware),
                URLQueryItem(name: "software", value: software)
            ]
        )
    }

    func deviceOverview() async throws -> KinoPubDeviceOverview {
        async let listResponse: DevicesResponse = get(path: "device", query: [])
        async let infoResponse: DeviceInfoResponse = get(path: "device/info", query: [])
        let (list, info) = try await (listResponse, infoResponse)
        let devices = list.devices.map(\.model).sorted {
            ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast)
        }
        return KinoPubDeviceOverview(devices: devices, currentDeviceID: info.device.id.value)
    }

    func removeDevice(id: String) async throws {
        let response: DeviceRemovalResponse = try await post(
            path: "device/\(id)/remove",
            query: []
        )
        if response.current?.value == true {
            throw KinoPubAPIError.authorizationFailed("Текущее устройство нельзя отвязать из WooF.Play")
        }
    }

    func toggleSubscription(id: String) async throws -> Bool {
        let response: ToggleWatchlistResponse = try await get(
            path: "watching/togglewatchlist",
            query: [URLQueryItem(name: "id", value: id)]
        )
        guard let watching = response.watching else {
            throw KinoPubAPIError.invalidResponse
        }
        return watching.value
    }

    func markTime(id: String, season: Int, episode: Int, seconds: Int) async throws {
        var query = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "video", value: String(max(episode, 1))),
            URLQueryItem(name: "time", value: String(max(seconds, 0)))
        ]
        if season > 0 { query.append(URLQueryItem(name: "season", value: String(season))) }
        let _: MarkTimeResponse = try await get(path: "watching/marktime", query: query)
    }

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        isRetry: Bool = false
    ) async throws -> T {
        let accessToken = try await validAccessToken()
        var components = URLComponents(
            url: KinoPubConfiguration.baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query + [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components.url else { throw KinoPubAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KinoPubAPIError.invalidResponse
        }
        if http.statusCode == 401, !isRetry {
            _ = try await refreshTokens()
            return try await get(path: path, query: query, isRetry: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KinoPubAPIError.server(http.statusCode, bodySnippet(data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KinoPubAPIError.decoding(error.localizedDescription)
        }
    }

    private func post<T: Decodable>(
        path: String,
        query: [URLQueryItem],
        isRetry: Bool = false
    ) async throws -> T {
        let accessToken = try await validAccessToken()
        var components = URLComponents(
            url: KinoPubConfiguration.baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query + [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components.url else { throw KinoPubAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KinoPubAPIError.invalidResponse
        }
        if http.statusCode == 401, !isRetry {
            _ = try await refreshTokens()
            return try await post(path: path, query: query, isRetry: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KinoPubAPIError.server(http.statusCode, bodySnippet(data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KinoPubAPIError.decoding(error.localizedDescription)
        }
    }

    private func validAccessToken() async throws -> String {
        guard let tokens else { throw KinoPubAPIError.notAuthenticated }
        if tokens.accessToken.isEmpty || tokens.expiresAt.timeIntervalSinceNow < 60 {
            return try await refreshTokens().accessToken
        }
        return tokens.accessToken
    }

    private func refreshTokens() async throws -> AuthTokens {
        guard let current = tokens, !current.refreshToken.isEmpty else {
            throw KinoPubAPIError.notAuthenticated
        }
        let response: TokenResponse = try await oauth([
            "grant_type": "refresh_token",
            "client_id": KinoPubConfiguration.clientID,
            "client_secret": KinoPubConfiguration.clientSecret,
            "refresh_token": current.refreshToken
        ])
        if let error = response.error {
            throw KinoPubAPIError.authorizationFailed(response.errorDescription ?? error)
        }
        let updated = try makeTokens(from: response, fallbackRefreshToken: current.refreshToken)
        tokens = updated
        try TokenStore.save(updated)
        return updated
    }

    private func oauth<T: Decodable>(_ parameters: [String: String]) async throws -> T {
        var components = URLComponents(
            url: KinoPubConfiguration.baseURL.appendingPathComponent("oauth2/device"),
            resolvingAgainstBaseURL: false
        )!
        if parameters["grant_type"] == "refresh_token" {
            components.path = "/oauth2/token"
        }
        components.queryItems = parameters
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        guard let url = components.url else { throw KinoPubAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KinoPubAPIError.invalidResponse
        }
        guard (200..<500).contains(http.statusCode) else {
            throw KinoPubAPIError.server(http.statusCode, bodySnippet(data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KinoPubAPIError.decoding(error.localizedDescription)
        }
    }

    private func makeTokens(
        from response: TokenResponse,
        fallbackRefreshToken: String?
    ) throws -> AuthTokens {
        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw KinoPubAPIError.invalidResponse
        }
        return AuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? fallbackRefreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        )
    }

    private func bodySnippet(_ data: Data) -> String {
        let value = String(data: data.prefix(240), encoding: .utf8) ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MarkTimeResponse: Decodable {
    let status: Int?
}

private struct ToggleWatchlistResponse: Decodable {
    let watching: FlexibleBool?
}
