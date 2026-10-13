import SwiftUI

struct WatchLaterView: View {
    @EnvironmentObject private var watchLater: WatchLaterStore

    var body: some View {
        NavigationStack {
            RemoteItemsGrid(
                items: watchLater.items,
                note: { item in
                    if let year = item.year { return String(year) }
                    return item.type
                },
                refresh: {},
                isLoadingMore: false,
                canLoadMore: false,
                errorMessage: nil,
                loadMore: {}
            )
            .navigationTitle("Буду смотреть")
            .navigationDestination(for: CatalogItem.self) { item in
                CatalogDetailView(itemID: item.id.value, placeholder: item)
            }
        }
    }
}

struct PersonalViewingView: View {
    @EnvironmentObject private var personalViewing: PersonalViewingStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Label(
                    "Список хранится только на этом устройстве и не отправляется в KinoPub.",
                    systemImage: "lock.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)

                RemoteItemsGrid(
                    items: personalViewing.items,
                    note: { item in
                        if let year = item.year { return String(year) }
                        return item.type
                    },
                    refresh: {},
                    isLoadingMore: false,
                    canLoadMore: false,
                    errorMessage: nil,
                    loadMore: {}
                )
            }
            .navigationTitle("Персональный просмотр")
            .navigationDestination(for: CatalogItem.self) { item in
                CatalogDetailView(itemID: item.id.value, placeholder: item)
            }
        }
    }
}

enum RemoteLibrarySection: String, Sendable {
    case collections
    case watching
    case subscriptions
    case bookmarks
    case history

    var title: String {
        switch self {
        case .collections: "Подборки"
        case .watching: "Я смотрю"
        case .subscriptions: "Подписки"
        case .bookmarks: "Закладки"
        case .history: "История"
        }
    }
}

struct RemoteLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var session: KinoPubSession
    let section: RemoteLibrarySection

    @State private var items: [CatalogItem] = []
    @State private var collections: [KinoCollection] = []
    @State private var bookmarks: [BookmarkFolder] = []
    @State private var history: [HistoryEntry] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var currentPage = 0
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var watchingType = "serials"
    @State private var activeRequestID = UUID()
    @State private var showsCreateBookmark = false
    @State private var newBookmarkTitle = ""
    @State private var pendingBookmarkDeletion: BookmarkFolder?
    @State private var isBookmarkMutation = false

    private let pageSize = 20
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            Group {
                if !session.isLoggedIn {
                    SignInView()
                } else if isLoading && isEmpty {
                    ProgressView("Загрузка…")
                } else if let errorMessage, isEmpty {
                    ContentUnavailableView {
                        Label("Не удалось загрузить", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Повторить") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    content
                }
            }
            .navigationTitle(section.title)
            .toolbar {
                if (section == .watching || section == .subscriptions) && session.isLoggedIn {
                    ToolbarItem(placement: .principal) {
                        if isCompact {
                            Menu {
                                Button("Сериалы") { watchingType = "serials" }
                                Button("Фильмы") { watchingType = "movies" }
                            } label: {
                                Label(watchingType == "serials" ? "Сериалы" : "Фильмы", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        } else {
                            Picker("Тип", selection: $watchingType) {
                                Text("Сериалы").tag("serials")
                                Text("Фильмы").tag("movies")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 260)
                        }
                    }
                }
                if session.isLoggedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await load() } } label: {
                            Label("Обновить", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
                if section == .bookmarks && session.isLoggedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newBookmarkTitle = ""
                            showsCreateBookmark = true
                        } label: {
                            Label("Создать группу", systemImage: "folder.badge.plus")
                        }
                        .disabled(isBookmarkMutation)
                    }
                }
            }
            .task(id: "\(section.rawValue):\(watchingType)") { await load() }
            .onDisappear {
                activeRequestID = UUID()
                isLoading = false
                isLoadingMore = false
            }
            .navigationDestination(for: CatalogItem.self) { item in
                CatalogDetailView(itemID: item.id.value, placeholder: item)
            }
            .navigationDestination(for: KinoCollection.self) { collection in
                RemoteFolderItemsView(title: collection.title, source: .collection(collection.id.value))
            }
            .navigationDestination(for: BookmarkFolder.self) { folder in
                RemoteFolderItemsView(title: folder.title, source: .bookmark(folder.id.value))
            }
            .alert("Новая группа закладок", isPresented: $showsCreateBookmark) {
                TextField("Название группы", text: $newBookmarkTitle)
                Button("Создать") { Task { await createBookmarkFolder() } }
                    .disabled(newBookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Группа будет синхронизирована с закладками вашего аккаунта KinoPub.")
            }
            .confirmationDialog(
                pendingBookmarkDeletion.map { "Удалить группу «\($0.title)»?" } ?? "Удалить группу?",
                isPresented: Binding(
                    get: { pendingBookmarkDeletion != nil },
                    set: { if !$0 { pendingBookmarkDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Удалить группу", role: .destructive) {
                    if let folder = pendingBookmarkDeletion {
                        Task { await deleteBookmarkFolder(folder) }
                    }
                    pendingBookmarkDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingBookmarkDeletion = nil }
            } message: {
                Text("Фильмы и сериалы будут удалены только из этой группы.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .collections:
            ScrollView {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 18) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection) {
                            CollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(isCompact ? 12 : 24)
                RemotePagingFooter(
                    isLoading: isLoadingMore,
                    canLoadMore: canLoadMore,
                    errorMessage: errorMessage,
                    loadMore: loadNextPage
                )
            }
            .refreshable { await load() }
        case .bookmarks:
            List {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "Нет групп",
                        systemImage: "bookmark",
                        description: Text("Создайте первую группу кнопкой вверху.")
                    )
                } else {
                    ForEach(bookmarks) { folder in
                        NavigationLink(value: folder) {
                            Label {
                                HStack {
                                    Text(folder.title)
                                    Spacer()
                                    if let count = folder.count { Text(String(count)).foregroundStyle(.secondary) }
                                }
                            } icon: {
                                Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Удалить", role: .destructive) {
                                pendingBookmarkDeletion = folder
                            }
                        }
                    }
                }
            }
            .refreshable { await load() }
        case .watching, .subscriptions:
            RemoteItemsGrid(
                items: visibleItems,
                note: { item in
                    guard let total = item.total, total > 0 else { return nil }
                    let base = "\(item.watched ?? 0)/\(total)"
                    return (item.newCount ?? 0) > 0 ? "\(base) · +\(item.newCount ?? 0) новых" : base
                },
                refresh: load,
                isLoadingMore: isLoadingMore,
                canLoadMore: canLoadMore,
                errorMessage: errorMessage,
                loadMore: loadNextPage
            )
        case .history:
            RemoteItemsGrid(
                items: history.map(\.item),
                note: { item in
                    guard let entry = history.first(where: { $0.item.id == item.id }) else { return nil }
                    if entry.season > 0 { return "S\(entry.season) E\(entry.episode)" }
                    if let date = entry.lastSeen { return date.formatted(date: .abbreviated, time: .shortened) }
                    return nil
                },
                refresh: load,
                isLoadingMore: isLoadingMore,
                canLoadMore: canLoadMore,
                errorMessage: errorMessage,
                loadMore: loadNextPage
            )
        }
    }

    private var visibleItems: [CatalogItem] {
        guard section == .subscriptions else { return items }
        return items.filter(session.isSubscribed)
    }

    private var isEmpty: Bool {
        switch section {
        case .collections: collections.isEmpty
        case .watching, .subscriptions: visibleItems.isEmpty
        case .bookmarks: bookmarks.isEmpty
        case .history: history.isEmpty
        }
    }

    private var cardColumns: [GridItem] {
        if isCompact {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        return [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 18)]
    }

    private func load() async {
        guard session.isLoggedIn else { return }
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if activeRequestID == requestID { isLoading = false }
        }

        do {
            switch section {
            case .collections:
                let loaded = try await session.collections(page: 1)
                guard activeRequestID == requestID else { return }
                collections = mergingCollections([], loaded)
                canLoadMore = !loaded.isEmpty
            case .watching, .subscriptions:
                let page = try await session.watching(
                    type: watchingType,
                    subscribed: section == .subscriptions,
                    page: 1
                )
                guard activeRequestID == requestID else { return }
                items = mergingCatalogItems([], page.items)
                if section == .subscriptions { session.rememberSubscriptionItems(page.items) }
                canLoadMore = page.hasPage(after: 1, requestedPageSize: pageSize)
            case .bookmarks:
                let loaded = try await session.bookmarks()
                guard activeRequestID == requestID else { return }
                bookmarks = loaded
                canLoadMore = false
            case .history:
                let page = try await session.history(page: 1)
                guard activeRequestID == requestID else { return }
                history = mergingHistory([], page.entries)
                canLoadMore = page.hasPage(after: 1, requestedPageSize: pageSize)
            }
            currentPage = 1
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = errorText(error)
        }
    }

    private func loadNextPage() async {
        guard session.isLoggedIn, !isLoading, !isLoadingMore, canLoadMore else { return }
        let requestID = activeRequestID
        let requestedPage = max(currentPage + 1, 2)
        isLoadingMore = true
        errorMessage = nil
        defer {
            if activeRequestID == requestID { isLoadingMore = false }
        }

        do {
            switch section {
            case .collections:
                let loaded = try await session.collections(page: requestedPage)
                guard activeRequestID == requestID else { return }
                let merged = mergingCollections(collections, loaded)
                canLoadMore = !loaded.isEmpty && merged.count > collections.count && requestedPage < 25
                collections = merged
            case .watching, .subscriptions:
                let page = try await session.watching(
                    type: watchingType,
                    subscribed: section == .subscriptions,
                    page: requestedPage
                )
                guard activeRequestID == requestID else { return }
                let merged = mergingCatalogItems(items, page.items)
                if section == .subscriptions { session.rememberSubscriptionItems(page.items) }
                canLoadMore = merged.count > items.count && page.hasPage(after: requestedPage, requestedPageSize: pageSize)
                items = merged
            case .history:
                let page = try await session.history(page: requestedPage)
                guard activeRequestID == requestID else { return }
                let merged = mergingHistory(history, page.entries)
                canLoadMore = merged.count > history.count && page.hasPage(after: requestedPage, requestedPageSize: pageSize)
                history = merged
            case .bookmarks:
                canLoadMore = false
            }
            currentPage = requestedPage
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = errorText(error)
        }
    }

    private func createBookmarkFolder() async {
        let title = newBookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isBookmarkMutation else { return }
        isBookmarkMutation = true
        errorMessage = nil
        defer { isBookmarkMutation = false }
        do {
            try await session.createBookmarkFolder(title: title)
            newBookmarkTitle = ""
            await load()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func deleteBookmarkFolder(_ folder: BookmarkFolder) async {
        guard !isBookmarkMutation else { return }
        isBookmarkMutation = true
        errorMessage = nil
        defer { isBookmarkMutation = false }
        do {
            try await session.removeBookmarkFolder(id: folder.id.value)
            bookmarks.removeAll { $0.id == folder.id }
        } catch {
            errorMessage = errorText(error)
        }
    }
}

private struct CollectionCard: View {
    let collection: KinoCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(
                urls: collection.posters?.candidateURLs ?? [],
                placeholderSystemImage: "square.grid.2x2"
            )
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(collection.title).font(.headline).lineLimit(2)
        }
    }
}

struct RemoteItemsGrid: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let items: [CatalogItem]
    let note: (CatalogItem) -> String?
    let refresh: () async -> Void
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let errorMessage: String?
    let loadMore: () async -> Void
    var removeFromBookmark: ((CatalogItem) -> Void)? = nil

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var columns: [GridItem] {
        if isCompact {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        return [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)]
    }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "film.stack")
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(items) { item in
                        CatalogGridTile(
                            item: item,
                            note: note(item),
                            onRemoveFromBookmark: removeFromBookmark.map { action in
                                { action(item) }
                            }
                        )
                    }
                }
                .padding(isCompact ? 12 : 24)
                RemotePagingFooter(
                    isLoading: isLoadingMore,
                    canLoadMore: canLoadMore,
                    errorMessage: errorMessage,
                    loadMore: loadMore
                )
            }
        }
        .refreshable { await refresh() }
    }
}

private enum RemoteFolderSource: Hashable {
    case collection(String)
    case bookmark(String)
}

private struct RemoteFolderItemsView: View {
    @EnvironmentObject private var session: KinoPubSession
    @EnvironmentObject private var library: MediaLibraryStore
    let title: String
    let source: RemoteFolderSource

    @State private var items: [CatalogItem] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var currentPage = 0
    @State private var canLoadMore = false
    @State private var errorMessage: String?
    @State private var activeRequestID = UUID()
    @State private var downloadRequest: DownloadRequest?
    @State private var isPreparingDownload = false
    @State private var preparationProgress = 0
    @State private var pendingItemRemoval: CatalogItem?
    @State private var isRemovingItem = false

    private let pageSize = 20

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Загрузка…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                RemoteItemsGrid(
                    items: items,
                    note: { _ in nil },
                    refresh: load,
                    isLoadingMore: isLoadingMore,
                    canLoadMore: canLoadMore,
                    errorMessage: errorMessage,
                    loadMore: loadNextPage,
                    removeFromBookmark: bookmarkRemovalAction
                )
            }
        }
        .navigationTitle(title)
        .toolbar {
            if case .collection(_) = source, !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await prepareWholeCollectionDownload() }
                    } label: {
                        if isPreparingDownload {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(preparationProgress > 0 ? "\(preparationProgress)" : "Подготовка")
                            }
                        } else {
                            Label("Скачать всю подборку", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .disabled(isPreparingDownload)
                }
            }
        }
        .task(id: source) { await load() }
        .sheet(item: $downloadRequest) { request in
            DownloadOptionsSheet(request: request)
        }
        .confirmationDialog(
            pendingItemRemoval.map { "Удалить «\($0.displayTitle)» из группы?" } ?? "Удалить из группы?",
            isPresented: Binding(
                get: { pendingItemRemoval != nil },
                set: { if !$0 { pendingItemRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить из группы", role: .destructive) {
                if let item = pendingItemRemoval {
                    Task { await removeFromBookmark(item) }
                }
                pendingItemRemoval = nil
            }
            Button("Отмена", role: .cancel) { pendingItemRemoval = nil }
        }
        .onDisappear {
            activeRequestID = UUID()
            isLoading = false
            isLoadingMore = false
        }
    }

    private var bookmarkRemovalAction: ((CatalogItem) -> Void)? {
        guard case .bookmark(_) = source else { return nil }
        return { pendingItemRemoval = $0 }
    }

    private func page(_ number: Int) async throws -> CatalogPage {
        switch source {
        case .collection(let id): try await session.collectionItems(id: id, page: number)
        case .bookmark(let id): try await session.bookmarkItems(id: id, page: number)
        }
    }

    private func load() async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        defer {
            if activeRequestID == requestID { isLoading = false }
        }
        do {
            let loaded = try await page(1)
            guard activeRequestID == requestID else { return }
            items = mergingCatalogItems([], loaded.items)
            currentPage = 1
            canLoadMore = loaded.hasPage(after: 1, requestedPageSize: pageSize)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = errorText(error)
        }
    }

    private func loadNextPage() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        let requestID = activeRequestID
        let requestedPage = max(currentPage + 1, 2)
        isLoadingMore = true
        errorMessage = nil
        defer {
            if activeRequestID == requestID { isLoadingMore = false }
        }
        do {
            let loaded = try await page(requestedPage)
            guard activeRequestID == requestID else { return }
            let merged = mergingCatalogItems(items, loaded.items)
            canLoadMore = merged.count > items.count && loaded.hasPage(after: requestedPage, requestedPageSize: pageSize)
            items = merged
            currentPage = requestedPage
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = errorText(error)
        }
    }

    private func removeFromBookmark(_ item: CatalogItem) async {
        guard case .bookmark(let folderID) = source, !isRemovingItem else { return }
        isRemovingItem = true
        errorMessage = nil
        defer { isRemovingItem = false }
        do {
            try await session.setBookmarkMembership(
                itemID: item.id.value,
                folderID: folderID,
                isMember: false
            )
            withAnimation { items.removeAll { $0.id == item.id } }
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func prepareWholeCollectionDownload() async {
        guard case .collection(_) = source, !isPreparingDownload else { return }
        isPreparingDownload = true
        preparationProgress = 0
        errorMessage = nil
        defer { isPreparingDownload = false }

        do {
            var allItems = items
            var nextPage = max(currentPage + 1, 2)
            var hasMore = canLoadMore
            while hasMore {
                let loaded = try await page(nextPage)
                let merged = mergingCatalogItems(allItems, loaded.items)
                hasMore = merged.count > allItems.count && loaded.hasPage(after: nextPage, requestedPageSize: pageSize)
                allItems = merged
                nextPage += 1
            }
            items = allItems
            currentPage = max(nextPage - 1, currentPage)
            canLoadMore = hasMore

            var candidates: [DownloadCandidate] = []
            for (index, summary) in allItems.enumerated() {
                guard !Task.isCancelled else { return }
                preparationProgress = index + 1
                let item = summary.playableItems.isEmpty
                    ? try await session.details(for: summary.id.value)
                    : summary
                let downloaded = library.downloadedEpisodeKeys(for: item.id.value)
                candidates.append(contentsOf: item.playableItems.compactMap { media in
                    downloaded.contains("\(media.season):\(media.episode)")
                        ? nil
                        : DownloadCandidate(item: item, media: media)
                })
            }

            guard !candidates.isEmpty else {
                errorMessage = "Все доступные видео из подборки уже скачаны."
                return
            }
            downloadRequest = DownloadRequest(title: title, candidates: candidates)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = errorText(error)
        }
    }
}

private struct RemotePagingFooter: View {
    let isLoading: Bool
    let canLoadMore: Bool
    let errorMessage: String?
    let loadMore: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView("Загружаю следующую страницу…")
                    .controlSize(.small)
            } else if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                Button("Повторить") { Task { await loadMore() } }.buttonStyle(.bordered)
            } else if canLoadMore {
                ProgressView().controlSize(.small).opacity(0.001)
                    .onAppear { Task { await loadMore() } }
                    .accessibilityLabel("Загрузка следующей страницы")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 24)
    }
}

private func mergingCollections(_ existing: [KinoCollection], _ additions: [KinoCollection]) -> [KinoCollection] {
    var seen = Set(existing.map(\.id.value))
    return existing + additions.filter { seen.insert($0.id.value).inserted }
}

private func mergingHistory(_ existing: [HistoryEntry], _ additions: [HistoryEntry]) -> [HistoryEntry] {
    var seen = Set(existing.map(\.id))
    return existing + additions.filter { seen.insert($0.id).inserted }
}

private func errorText(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
