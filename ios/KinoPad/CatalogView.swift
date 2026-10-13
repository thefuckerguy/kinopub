import SwiftUI

struct CatalogView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var session: KinoPubSession
    let initialList: CatalogList?
    let screenTitle: String
    @State private var searchText = ""

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var columns: [GridItem] {
        if isCompact {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        return [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]
    }

    init(initialList: CatalogList? = nil, title: String = "Каталог") {
        self.initialList = initialList
        self.screenTitle = title
    }

    var body: some View {
        NavigationStack {
            Group {
                if !session.isLoggedIn {
                    SignInView()
                } else if session.isLoading && session.items.isEmpty {
                    ProgressView("Загрузка каталога…")
                } else if session.items.isEmpty {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "magnifyingglass",
                        description: Text("Измените запрос или обновите каталог.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                                ForEach(session.items) { item in
                                    CatalogGridTile(item: item, note: nil)
                                }
                            }
                            CatalogPagingFooter()
                                .padding(.vertical, 12)
                        }
                        .padding(isCompact ? 12 : 16)
                    }
                    .refreshable { await session.reloadCurrentCatalog() }
                }
            }
            .navigationTitle(screenTitle)
            .searchable(text: $searchText, prompt: "Фильм или сериал")
            .onSubmit(of: .search) {
                Task { await session.search(searchText) }
            }
            .onChange(of: searchText) { _, value in
                if value.isEmpty, session.isLoggedIn {
                    Task { await session.loadCatalog() }
                }
            }
            .toolbar {
                if session.isLoggedIn {
                    ToolbarItem(placement: .principal) {
                        if isCompact {
                            Menu {
                                ForEach(CatalogList.allCases) { list in
                                    Button {
                                        session.selectedList = list
                                    } label: {
                                        if session.selectedList == list {
                                            Label(list.title, systemImage: "checkmark")
                                        } else {
                                            Text(list.title)
                                        }
                                    }
                                }
                            } label: {
                                Label(session.selectedList.title, systemImage: "line.3.horizontal.decrease.circle")
                                    .lineLimit(1)
                            }
                        } else {
                            Picker("Раздел", selection: $session.selectedList) {
                                ForEach(CatalogList.allCases) { list in
                                    Text(list.title).tag(list)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await session.reloadCurrentCatalog() }
                        } label: {
                            Label("Обновить", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            .onChange(of: session.selectedList) { _, _ in
                searchText = ""
                Task { await session.loadCatalog() }
            }
            .task {
                if let initialList, session.selectedList != initialList {
                    session.selectedList = initialList
                }
                if session.isLoggedIn && session.items.isEmpty {
                    await session.loadCatalog()
                }
            }
            .navigationDestination(for: CatalogItem.self) { item in
                CatalogDetailView(itemID: item.id.value, placeholder: item)
            }
            .alert(
                "KinoPub",
                isPresented: Binding(
                    get: { session.errorMessage != nil },
                    set: { if !$0 { session.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "Неизвестная ошибка")
            }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var session: KinoPubSession

    var body: some View {
        VStack(spacing: 20) {
            Image("WooFMascot")
                .resizable().scaledToFill()
                .frame(width: 116, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(KinoPadTheme.gold.opacity(0.75)))
                .shadow(color: KinoPadTheme.violet.opacity(0.45), radius: 22)
            Text("Добро пожаловать в WooF.Play")
                .font(.largeTitle.bold())
            Text("Каталог и онлайн‑просмотр требуют аккаунт с активной подпиской. Локальная медиатека работает без входа.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            if let challenge = session.challenge {
                Text(challenge.userCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
                Link("Открыть kino.watch/device", destination: challenge.verificationURL)
                    .buttonStyle(.borderedProminent)
                HStack {
                    ProgressView()
                    Text("Ожидаю подтверждения…")
                }
                Button("Отмена", role: .cancel) { session.cancelLogin() }
            } else {
                Button {
                    session.startLogin()
                } label: {
                    Label("Получить код входа", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isSigningIn)
            }
        }
        .padding(32)
    }
}

struct CatalogCard: View {
    let item: CatalogItem
    @ScaledMetric(relativeTo: .headline) private var titleSlotHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var metadataSlotHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(urls: item.posters?.candidateURLs ?? [])
                .frame(maxWidth: .infinity)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.displayTitle)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: titleSlotHeight, maxHeight: titleSlotHeight, alignment: .topLeading)
            HStack {
                if let year = item.year { Text(String(year)) }
                Spacer()
                if let rating = item.ratingText { Text(rating) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: metadataSlotHeight, maxHeight: metadataSlotHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CatalogGridTile: View {
    let item: CatalogItem
    let note: String?
    var onRemoveFromBookmark: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .caption) private var noteSlotHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            NavigationLink(value: item) {
                CatalogCard(item: item)
            }
            .buttonStyle(.plain)

            Text(note ?? " ")
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .opacity(note == nil ? 0 : 1)
                .frame(maxWidth: .infinity, minHeight: noteSlotHeight, maxHeight: noteSlotHeight, alignment: .leading)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                WatchLaterButton(item: item, compact: true)
                BookmarkButton(item: item, compact: true)
                PersonalViewingButton(item: item, compact: true)
                SubscriptionButton(item: item, compact: true)
                if let onRemoveFromBookmark {
                    Button(role: .destructive, action: onRemoveFromBookmark) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Удалить из этой группы закладок")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchLaterButton: View {
    @EnvironmentObject private var watchLater: WatchLaterStore
    let item: CatalogItem
    var compact = false

    var body: some View {
        let isSaved = watchLater.contains(item)
        Button {
            watchLater.toggle(item)
        } label: {
            if compact {
                Image(systemName: isSaved ? "eye.fill" : "eye")
            } else {
                Label(
                    isSaved ? "Буду смотреть" : "Смотреть позже",
                    systemImage: isSaved ? "eye.fill" : "eye"
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .mini : .large)
        .tint(isSaved ? KinoPadTheme.gold : nil)
        .accessibilityLabel(isSaved ? "Убрать из раздела Буду смотреть" : "Добавить в раздел Буду смотреть")
    }
}

struct PersonalViewingButton: View {
    @EnvironmentObject private var personalViewing: PersonalViewingStore
    let item: CatalogItem
    var compact = false

    var body: some View {
        let isSaved = personalViewing.contains(item)
        Button {
            personalViewing.toggle(item)
        } label: {
            if compact {
                Image(systemName: isSaved ? "lock.fill" : "lock.open")
            } else {
                Label(
                    isSaved ? "В персональном" : "В персональный просмотр",
                    systemImage: isSaved ? "lock.fill" : "lock.open"
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .mini : .large)
        .tint(isSaved ? KinoPadTheme.violet : nil)
        .accessibilityLabel(
            isSaved
                ? "Убрать из персонального просмотра"
                : "Добавить в персональный просмотр"
        )
    }
}

struct BookmarkButton: View {
    @EnvironmentObject private var session: KinoPubSession
    let item: CatalogItem
    var compact = false

    @State private var showsFolders = false

    var body: some View {
        Button {
            showsFolders = true
        } label: {
            if compact {
                Image(systemName: "bookmark")
            } else {
                Label("Добавить в закладки", systemImage: "bookmark")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .mini : .large)
        .disabled(!session.isLoggedIn)
        .accessibilityLabel("Управлять группами закладок")
        .sheet(isPresented: $showsFolders) {
            BookmarkMembershipSheet(item: item)
        }
    }
}

private struct BookmarkMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: KinoPubSession

    let item: CatalogItem

    @State private var folders: [BookmarkFolder] = []
    @State private var memberFolderIDs = Set<String>()
    @State private var updatingFolderIDs = Set<String>()
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var newFolderTitle = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoading {
                        ProgressView("Загружаю группы…")
                    } else if folders.isEmpty {
                        ContentUnavailableView(
                            "Нет групп",
                            systemImage: "bookmark",
                            description: Text("Создайте группу ниже, затем добавьте в неё фильм или сериал.")
                        )
                    } else {
                        ForEach(folders) { folder in
                            Button {
                                Task { await toggle(folder) }
                            } label: {
                                HStack {
                                    Image(systemName: memberFolderIDs.contains(folder.id.value) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(memberFolderIDs.contains(folder.id.value) ? KinoPadTheme.gold : .secondary)
                                    Text(folder.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if updatingFolderIDs.contains(folder.id.value) {
                                        ProgressView().controlSize(.small)
                                    } else if let count = folder.count {
                                        Text(String(count)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(updatingFolderIDs.contains(folder.id.value))
                        }
                    }
                } header: {
                    Text("Группы для «\(item.displayTitle)»")
                }

                Section("Новая группа") {
                    TextField("Название", text: $newFolderTitle)
                    Button {
                        Task { await createFolder() }
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Label("Создать группу", systemImage: "folder.badge.plus")
                        }
                    }
                    .disabled(isCreating || newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Закладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let allFolders = session.bookmarks()
            async let memberships = session.bookmarkFolders(for: item.id.value)
            let (loadedFolders, loadedMemberships) = try await (allFolders, memberships)
            folders = loadedFolders
            memberFolderIDs = Set(loadedMemberships.map { $0.id.value })
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func createFolder() async {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            try await session.createBookmarkFolder(title: title)
            newFolderTitle = ""
            await reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func toggle(_ folder: BookmarkFolder) async {
        let folderID = folder.id.value
        guard !updatingFolderIDs.contains(folderID) else { return }
        updatingFolderIDs.insert(folderID)
        errorMessage = nil
        defer { updatingFolderIDs.remove(folderID) }
        let shouldAdd = !memberFolderIDs.contains(folderID)
        do {
            try await session.setBookmarkMembership(
                itemID: item.id.value,
                folderID: folderID,
                isMember: shouldAdd
            )
            if shouldAdd {
                memberFolderIDs.insert(folderID)
            } else {
                memberFolderIDs.remove(folderID)
            }
        } catch {
            errorMessage = errorText(error)
        }
    }
}

struct SubscriptionButton: View {
    @EnvironmentObject private var session: KinoPubSession
    let item: CatalogItem
    var compact = false

    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task {
                do {
                    _ = try await session.toggleSubscription(for: item)
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        } label: {
            if session.isUpdatingSubscription(item.id.value) {
                ProgressView().controlSize(.small)
            } else if compact {
                Image(systemName: session.isSubscribed(item) ? "bell.fill" : "bell.badge")
            } else {
                Label(
                    session.isSubscribed(item) ? "В подписке" : "Подписаться",
                    systemImage: session.isSubscribed(item) ? "bell.fill" : "bell.badge"
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .mini : .large)
        .tint(session.isSubscribed(item) ? KinoPadTheme.gold : nil)
        .disabled(session.isUpdatingSubscription(item.id.value))
        .accessibilityLabel(session.isSubscribed(item) ? "Убрать из подписок" : "Добавить в подписки")
        .alert("Не удалось изменить подписку", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }
}

private struct CatalogPagingFooter: View {
    @EnvironmentObject private var session: KinoPubSession

    var body: some View {
        VStack(spacing: 10) {
            if session.currentPage > 0 {
                Text(pageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.isLoadingMore {
                ProgressView("Загружаю следующую страницу…")
                    .controlSize(.small)
            } else if session.canLoadMore {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.001)
                    .onAppear { Task { await session.loadNextCatalogPage() } }
                    .accessibilityLabel("Загрузка следующей страницы")
            } else if session.currentPage > 1 {
                Label("Все страницы загружены", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pageLabel: String {
        if let totalPages = session.totalPages, totalPages > 0 {
            return "Страница \(session.currentPage) из \(totalPages)"
        }
        return "Страница \(session.currentPage)"
    }
}

struct DownloadCandidate: Identifiable {
    let item: CatalogItem
    let media: PlayableMedia

    var id: String { "\(item.id.value):\(media.id)" }
}

struct DownloadRequest: Identifiable {
    let id = UUID()
    let title: String
    let candidates: [DownloadCandidate]
    let allowsMediaSelection: Bool

    var item: CatalogItem? { candidates.first?.item }
    var mediaItems: [PlayableMedia] { candidates.map(\.media) }

    init(item: CatalogItem, media: PlayableMedia) {
        title = item.displayTitle
        candidates = [DownloadCandidate(item: item, media: media)]
        allowsMediaSelection = false
    }

    init(
        item: CatalogItem,
        mediaItems: [PlayableMedia],
        title: String? = nil,
        allowsMediaSelection: Bool = false
    ) {
        self.title = title ?? item.displayTitle
        candidates = mediaItems.map { DownloadCandidate(item: item, media: $0) }
        self.allowsMediaSelection = allowsMediaSelection
    }

    init(title: String, candidates: [DownloadCandidate]) {
        self.title = title
        self.candidates = candidates
        allowsMediaSelection = false
    }
}

struct DownloadOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var downloads: OfflineDownloadManager
    let request: DownloadRequest

    @State private var selectedVariantID: String
    @State private var selectedAudioIndex = -1
    @State private var selectedDestinationID = OfflineDownloadDestination.internalID
    @State private var selectedCandidateIDs: Set<String>

    init(request: DownloadRequest) {
        self.request = request
        _selectedVariantID = State(initialValue: request.mediaItems.first?.downloadVariants.first?.id ?? "auto")
        _selectedCandidateIDs = State(initialValue: Set(request.candidates.map(\.id)))
    }

    private var selectedCandidates: [DownloadCandidate] {
        request.candidates.filter { selectedCandidateIDs.contains($0.id) }
    }
    private var selectedMediaItems: [PlayableMedia] { selectedCandidates.map(\.media) }
    private var referenceMedia: PlayableMedia? { selectedMediaItems.first ?? request.mediaItems.first }
    private var variants: [DownloadVariant] { referenceMedia?.downloadVariants ?? [] }
    private var audioTracks: [CatalogAudio] {
        (referenceMedia?.audioTracks ?? []).sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
    }
    private var destinations: [OfflineDownloadDestination] { library.downloadDestinations }
    private var selectedDestination: OfflineDownloadDestination? {
        destinations.first(where: { $0.id == selectedDestinationID }) ?? destinations.first(where: \.isInternal)
    }
    private var selectedReferenceVariant: DownloadVariant? {
        variants.first(where: { $0.id == selectedVariantID }) ?? variants.first
    }
    private var canSaveToSelectedDestination: Bool {
        guard selectedDestination?.isInternal == false else { return true }
        return selectedMediaItems.allSatisfy { variant(for: $0)?.directFileURL != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Загрузка") {
                    LabeledContent("Название", value: request.title)
                    if Set(request.candidates.map { $0.item.id.value }).count > 1 {
                        LabeledContent("Фильмов и сериалов", value: String(Set(request.candidates.map { $0.item.id.value }).count))
                    }
                    if request.mediaItems.count > 1 {
                        LabeledContent(
                            request.allowsMediaSelection ? "Выбрано серий" : "Серий",
                            value: request.allowsMediaSelection
                                ? "\(selectedCandidates.count) из \(request.mediaItems.count)"
                                : String(request.mediaItems.count)
                        )
                    } else if let media = referenceMedia {
                        LabeledContent("Видео", value: media.season > 0 ? "S\(media.season) E\(media.episode)" : media.title)
                    }
                }

                if request.allowsMediaSelection && request.candidates.count > 1 {
                    Section {
                        HStack {
                            Button("Выбрать все") {
                                selectedCandidateIDs = Set(request.candidates.map(\.id))
                            }
                            Spacer()
                            Button("Снять все") { selectedCandidateIDs.removeAll() }
                        }
                        ForEach(request.candidates) { candidate in
                            Button {
                                if selectedCandidateIDs.contains(candidate.id) {
                                    selectedCandidateIDs.remove(candidate.id)
                                } else {
                                    selectedCandidateIDs.insert(candidate.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedCandidateIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedCandidateIDs.contains(candidate.id) ? KinoPadTheme.gold : .secondary)
                                    Text(episodeSelectionLabel(candidate.media))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Выберите серии")
                    } footer: {
                        Text("Можно скачать весь сезон или оставить отмеченными только нужные серии.")
                    }
                }

                Section("Качество") {
                    if variants.isEmpty {
                        Text("Автоматически").foregroundStyle(.secondary)
                    } else {
                        Picker("Качество видео", selection: $selectedVariantID) {
                            ForEach(variants) { variant in
                                Text(variant.displayName).tag(variant.id)
                            }
                        }
                        .pickerStyle(.inline)
                        if selectedMediaItems.count > 1 {
                            Text("Для каждой серии будет выбрано ближайшее доступное качество.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Озвучка") {
                    Picker("Аудиодорожка", selection: $selectedAudioIndex) {
                        Text("Автоматически").tag(-1)
                        ForEach(Array(audioTracks.enumerated()), id: \.offset) { index, track in
                            Text(track.displayName).tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Куда сохранить") {
                    Picker("Хранилище", selection: $selectedDestinationID) {
                        ForEach(destinations) { destination in
                            Label(
                                destination.name,
                                systemImage: destination.isInternal ? AppDevice.storageSystemImage : "externaldrive"
                            )
                            .tag(destination.id)
                        }
                    }
                    .pickerStyle(.inline)

                    if destinations.count == 1 {
                        Text("Чтобы сохранять на внешний диск, сначала подключите его папку в офлайн-библиотеке.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !canSaveToSelectedDestination {
                        Label(
                            "Для выбранного качества сервер не предоставил отдельный файл. Выберите другое качество или сохранение на \(AppDevice.platformName).",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Параметры загрузки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Скачать") {
                        startDownloads()
                        dismiss()
                    }
                    .disabled(selectedCandidates.isEmpty || !canSaveToSelectedDestination)
                }
            }
            .onAppear {
                if !destinations.contains(where: { $0.id == selectedDestinationID }) {
                    selectedDestinationID = destinations.first?.id ?? OfflineDownloadDestination.internalID
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func variant(for media: PlayableMedia) -> DownloadVariant? {
        guard let reference = selectedReferenceVariant else { return media.downloadVariants.first }
        return media.downloadVariants.first(where: { $0.height == reference.height && $0.codec == reference.codec })
            ?? media.downloadVariants.first(where: { $0.height == reference.height })
            ?? media.downloadVariants.first
    }

    private func startDownloads() {
        for candidate in selectedCandidates {
            downloads.enqueue(
                item: candidate.item,
                media: candidate.media,
                variant: variant(for: candidate.media),
                audioTrackIndex: selectedAudioIndex >= 0 ? selectedAudioIndex : nil,
                destination: selectedDestination
            )
        }
    }

    private func episodeSelectionLabel(_ media: PlayableMedia) -> String {
        media.season > 0
            ? "S\(media.season) E\(media.episode) · \(media.title)"
            : media.title
    }
}

private struct PlayableSeasonSection: Identifiable {
    let season: Int
    let mediaItems: [PlayableMedia]

    var id: Int { season }
    var title: String { season > 0 ? "Сезон \(season)" : "Без сезона" }
}

struct CatalogDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var session: KinoPubSession
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @EnvironmentObject private var progress: PlaybackProgressStore
    let itemID: String
    let placeholder: CatalogItem

    @State private var item: CatalogItem?
    @State private var selectedMedia: PlayableMedia?
    @State private var downloadRequest: DownloadRequest?
    @State private var loadingError: String?

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var displayedItem: CatalogItem { item ?? placeholder }
    private var hasSeasons: Bool { displayedItem.playableItems.contains { $0.season > 0 } }
    private var seasonSections: [PlayableSeasonSection] {
        Dictionary(grouping: displayedItem.playableItems, by: \.season)
            .map { season, mediaItems in
                PlayableSeasonSection(
                    season: season,
                    mediaItems: mediaItems.sorted {
                        if $0.episode != $1.episode { return $0.episode < $1.episode }
                        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted { $0.season < $1.season }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader

                if let plot = displayedItem.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if !displayedItem.playableItems.isEmpty {
                    Text(hasSeasons ? "Серии" : "Видео")
                        .font(.title2.bold())
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(seasonSections) { section in
                            if hasSeasons {
                                let downloaded = library.downloadedEpisodeKeys(for: displayedItem.id.value)
                                let downloadable = section.mediaItems.filter {
                                    !downloaded.contains("\($0.season):\($0.episode)") &&
                                        !downloads.isQueued(
                                            catalogID: displayedItem.id.value,
                                            season: $0.season,
                                            episode: $0.episode
                                        )
                                }
                                seasonHeader(section: section, downloadable: downloadable)
                                .padding(.top, section.season == seasonSections.first?.season ? 0 : 10)
                            }
                            ForEach(section.mediaItems) { media in
                                mediaRow(media)
                                Divider()
                            }
                        }
                    }
                } else if item == nil {
                    ProgressView("Получаю доступные видео…")
                }

                if let loadingError {
                    Label(loadingError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(isCompact ? 16 : 24)
        }
        .navigationTitle(displayedItem.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                item = try await session.details(for: itemID)
            } catch {
                loadingError = error.localizedDescription
            }
        }
        .fullScreenCover(item: $selectedMedia) { media in
            VideoPlayerScreen(
                url: media.manifestURL,
                title: media.title,
                compatibilityWarning: nil,
                context: .online(catalogID: displayedItem.id.value, media: media),
                audioTracks: media.audioTracks,
                onClose: { selectedMedia = nil }
            )
        }
        .sheet(item: $downloadRequest) { request in
            DownloadOptionsSheet(request: request)
        }
    }

    @ViewBuilder
    private var detailHeader: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 18) {
                detailPoster.frame(maxWidth: .infinity)
                detailMetadata
            }
        } else {
            HStack(alignment: .top, spacing: 24) {
                detailPoster
                detailMetadata
            }
        }
    }

    private var detailPoster: some View {
        PosterImage(urls: displayedItem.posters?.candidateURLs ?? [])
            .frame(width: isCompact ? 180 : 220, height: isCompact ? 270 : 330)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var detailMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayedItem.displayTitle)
                .font(isCompact ? .title.bold() : .largeTitle.bold())
            if let originalTitle = displayedItem.originalTitle {
                Text(originalTitle).foregroundStyle(.secondary)
            }
            HStack {
                if let year = displayedItem.year { Text(String(year)) }
                if let rating = displayedItem.ratingText { Text(rating) }
            }
            .font(.headline)
            if let genres = displayedItem.genres {
                Text(genres.compactMap(\.title).joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            if let first = displayedItem.playableItems.first {
                primaryActions(for: first)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    WatchLaterButton(item: displayedItem)
                    BookmarkButton(item: displayedItem)
                    PersonalViewingButton(item: displayedItem)
                    SubscriptionButton(item: displayedItem)
                }
                VStack(alignment: .leading) {
                    WatchLaterButton(item: displayedItem)
                    BookmarkButton(item: displayedItem)
                    PersonalViewingButton(item: displayedItem)
                    SubscriptionButton(item: displayedItem)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func primaryActions(for first: PlayableMedia) -> some View {
        if isCompact {
            VStack(spacing: 10) {
                playbackButton(for: first).frame(maxWidth: .infinity)
                downloadAllButton.frame(maxWidth: .infinity)
            }
        } else {
            HStack {
                playbackButton(for: first)
                downloadAllButton
            }
        }
    }

    private func playbackButton(for first: PlayableMedia) -> some View {
        let context = PlaybackContext.online(catalogID: displayedItem.id.value, media: first)
        let resume = progress.resumePosition(for: context)
        return Button {
            selectedMedia = first
        } label: {
            Label(
                resume > 5 && !(progress.isWatched(context.key) || first.isWatched)
                    ? "Продолжить с \(Self.timecode(resume))"
                    : "Открыть во весь экран",
                systemImage: "arrow.up.left.and.arrow.down.right"
            )
            .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var downloadAllButton: some View {
        Button {
            let downloaded = library.downloadedEpisodeKeys(for: displayedItem.id.value)
            let missing = displayedItem.playableItems.filter {
                !downloaded.contains("\($0.season):\($0.episode)")
            }
            downloadRequest = DownloadRequest(item: displayedItem, mediaItems: missing)
        } label: {
            Label("Скачать", systemImage: "arrow.down.circle")
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private func seasonHeader(section: PlayableSeasonSection, downloadable: [PlayableMedia]) -> some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 8) {
                seasonTitle(section)
                seasonDownloadControl(section: section, downloadable: downloadable)
            }
        } else {
            HStack {
                seasonTitle(section)
                Spacer()
                seasonDownloadControl(section: section, downloadable: downloadable)
            }
        }
    }

    private func seasonTitle(_ section: PlayableSeasonSection) -> some View {
        Text("\(section.title) · \(section.mediaItems.count) эп.")
            .font(.headline)
            .foregroundStyle(KinoPadTheme.gold)
    }

    @ViewBuilder
    private func seasonDownloadControl(section: PlayableSeasonSection, downloadable: [PlayableMedia]) -> some View {
        if downloadable.isEmpty {
            Label("Сезон скачан", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Button {
                downloadRequest = DownloadRequest(
                    item: displayedItem,
                    mediaItems: downloadable,
                    title: "\(displayedItem.displayTitle) · \(section.title)",
                    allowsMediaSelection: true
                )
            } label: {
                Label("Скачать сезон", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func mediaRow(_ media: PlayableMedia) -> some View {
        let mediaContext = PlaybackContext.online(catalogID: displayedItem.id.value, media: media)
        let key = mediaContext.key
        let resume = progress.resumePosition(for: mediaContext)
        let watched = progress.isWatched(key) || media.isWatched
        let downloaded = library.downloadedEpisodeKeys(for: displayedItem.id.value)
            .contains("\(media.season):\(media.episode)")

        return HStack(spacing: 12) {
            Button { selectedMedia = media } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if media.season > 0 {
                        Text("E\(media.episode)")
                            .font(.caption.monospacedDigit())
                    }
                    Text(media.title)
                }
                if let duration = media.duration, duration > 0 {
                    Text(Self.durationText(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if resume > 5 && !watched {
                    Text("Продолжить с \(Self.timecode(resume))")
                        .font(.caption)
                        .foregroundStyle(KinoPadTheme.gold)
                }
            }
            Spacer()
            Button {
                progress.setWatched(!watched, key: key, duration: media.duration)
            } label: {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(watched ? .green : .secondary)
            }
            .buttonStyle(.plain)

            if downloaded {
                Image(systemName: "checkmark.icloud.fill").foregroundStyle(.green)
            } else if downloads.isQueued(
                catalogID: displayedItem.id.value,
                season: media.season,
                episode: media.episode
            ) {
                ProgressView().controlSize(.small)
            } else {
                Button { downloadRequest = DownloadRequest(item: displayedItem, media: media) } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    private static func durationText(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    private static func timecode(_ seconds: Double) -> String {
        let value = max(Int(seconds), 0)
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private func errorText(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
