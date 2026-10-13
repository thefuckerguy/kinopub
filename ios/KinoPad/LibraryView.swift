import SwiftUI
import UniformTypeIdentifiers

private enum OfflineTypeFilter: String, CaseIterable, Identifiable {
    case all, movies, series
    var id: Self { self }
    var title: String { self == .all ? "Все" : self == .movies ? "Фильмы" : "Сериалы" }
}

private enum OfflineSort: String, CaseIterable, Identifiable {
    case recent, title, size
    var id: Self { self }
    var title: String { self == .recent ? "Сначала новые" : self == .title ? "По названию" : "По размеру" }
}

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: MediaLibraryStore
    @EnvironmentObject private var downloads: OfflineDownloadManager
    @State private var showsFolderImporter = false
    @State private var showsSources = false
    @State private var searchText = ""
    @State private var typeFilter: OfflineTypeFilter = .all
    @State private var sort: OfflineSort = .recent
    @State private var genre = ""
    @State private var pendingTitleDeletion: OfflineTitle?
    @AppStorage("offlineLibraryUsesGrid") private var usesGrid = true

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var libraryColumns: [GridItem] {
        if isCompact {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
        return [GridItem(.adaptive(minimum: 158, maximum: 220), spacing: 20)]
    }

    private var genres: [String] { Array(Set(store.titles.flatMap(\.genres))).sorted() }

    private var filteredTitles: [OfflineTitle] {
        let terms = searchText.lowercased().split(whereSeparator: \.isWhitespace)
        return store.titles.filter { title in
            let typeMatches = typeFilter == .all || (typeFilter == .movies ? title.isMovie : !title.isMovie)
            let genreMatches = genre.isEmpty || title.genres.contains(genre)
            let haystack = ([title.title, title.originalTitle ?? ""] + title.genres).joined(separator: " ").lowercased()
            return typeMatches && genreMatches && terms.allSatisfy { haystack.contains($0) }
        }.sorted { lhs, rhs in
            switch sort {
            case .recent: return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            case .title: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .size: return lhs.totalBytes > rhs.totalBytes
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    downloadJobs
                    filters
                    libraryContent
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(.horizontal, isCompact ? 12 : 24)
                .padding(.vertical, isCompact ? 14 : 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(KinoPadTheme.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OfflineTitle.self) { title in
                OfflineTitleDetailView(title: title)
            }
            .fileImporter(
                isPresented: $showsFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): store.addFolders(urls)
                case .failure(let error): store.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showsSources) {
                NavigationStack { SourceManagerView(showsFolderImporter: $showsFolderImporter) }
                    .presentationDetents([.medium, .large])
            }
            .alert(
                "Ошибка доступа",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Неизвестная ошибка")
            }
            .confirmationDialog(
                pendingTitleDeletion.map { "Удалить «\($0.title)» с \(AppDevice.platformName)?" } ?? "Удалить с \(AppDevice.platformName)?",
                isPresented: Binding(
                    get: { pendingTitleDeletion != nil },
                    set: { if !$0 { pendingTitleDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Удалить с \(AppDevice.platformName)", role: .destructive) {
                    if let title = pendingTitleDeletion {
                        store.deleteFromDevice(title: title)
                    }
                    pendingTitleDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingTitleDeletion = nil }
            } message: {
                Text("Скачанные файлы будут удалены без возможности отмены. Файлы на внешних дисках не затрагиваются.")
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                headerActions
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                headerTitle
                Spacer()
                headerActions
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Офлайн библиотека")
                .font(isCompact ? .title.bold() : .largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(store.isScanning ? "Сканирую подключённые папки…" : "Фильмы и сериалы на \(AppDevice.platformName) и внешних дисках")
                .foregroundStyle(.secondary)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button { showsSources = true } label: {
                Label("Папки и диски", systemImage: "externaldrive")
            }
            .buttonStyle(.bordered)
            Button { store.rescan() } label: {
                Label("Пересканировать", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isScanning)
        }
        .controlSize(isCompact ? .small : .regular)
    }

    @ViewBuilder
    private var downloadJobs: some View {
        let visible = downloads.jobs.filter { $0.status != .finished || $0.errorMessage != nil }
        if !visible.isEmpty || downloads.jobs.contains(where: { $0.status == .finished }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(visible.isEmpty ? "ЗАВЕРШЁННЫЕ ЗАГРУЗКИ" : "ЗАГРУЗКИ")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                    if downloads.jobs.contains(where: { $0.status == .finished || $0.status == .failed }) {
                        Button("Очистить завершённые") { downloads.clearFinished() }
                            .font(.caption).buttonStyle(.bordered)
                    }
                }
                ForEach(visible) { job in
                    HStack(spacing: 12) {
                        Image(systemName: job.status == .failed ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(job.status == .failed ? .red : KinoPadTheme.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(job.title) · \(job.episodeLabel)").font(.subheadline.weight(.medium))
                            if let summary = job.optionSummary {
                                Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let error = job.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                            } else {
                                ProgressView(value: job.progress).tint(KinoPadTheme.gold)
                            }
                        }
                        Spacer()
                        if job.status == .waiting || job.status == .downloading {
                            Button(role: .destructive) { downloads.cancel(jobID: job.id) } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск по названию или жанру…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13).frame(height: 44)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.08)))

            if isCompact {
                ScrollView(.horizontal, showsIndicators: false) {
                    typeFilterButtons
                }
                HStack(spacing: 6) {
                    filterMenus
                    Spacer(minLength: 0)
                    viewModeButtons
                }
            } else {
                HStack(spacing: 10) {
                    typeFilterButtons
                    Spacer()
                    filterMenus
                    viewModeButtons
                }
            }
        }
    }

    private var typeFilterButtons: some View {
        HStack(spacing: 3) {
            ForEach(OfflineTypeFilter.allCases) { filter in
                Button { typeFilter = filter } label: {
                    Text("\(filter.title) \(count(for: filter))")
                        .font(.subheadline.weight(typeFilter == filter ? .semibold : .regular))
                        .padding(.horizontal, isCompact ? 11 : 15).frame(height: 34)
                        .background(typeFilter == filter ? KinoPadTheme.gold.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(typeFilter == filter ? KinoPadTheme.gold : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06)))
    }

    @ViewBuilder
    private var filterMenus: some View {
        if !genres.isEmpty {
            Picker("Жанр", selection: $genre) {
                Text("Все жанры").tag("")
                ForEach(genres, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        }
        Picker("Сортировка", selection: $sort) {
            ForEach(OfflineSort.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
    }

    private var viewModeButtons: some View {
        HStack(spacing: 2) {
            viewButton(grid: false, icon: "list.bullet")
            viewButton(grid: true, icon: "square.grid.2x2")
        }
        .padding(3).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private var libraryContent: some View {
        if store.isScanning && store.titles.isEmpty {
            HStack { Spacer(); ProgressView("Сканирование…"); Spacer() }.padding(.top, 80)
        } else if store.titles.isEmpty {
            ContentUnavailableView {
                Label("Видео не найдены", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("Подключите папку внешнего диска или скопируйте видео в WooF.Play через приложение «Файлы».")
            } actions: {
                Button("Подключить папку") { showsFolderImporter = true }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.top, 70)
        } else if filteredTitles.isEmpty {
            ContentUnavailableView.search(text: searchText).frame(maxWidth: .infinity).padding(.top, 70)
        } else if usesGrid {
            LazyVGrid(columns: libraryColumns, alignment: .leading, spacing: isCompact ? 18 : 24) {
                ForEach(filteredTitles) { title in
                    NavigationLink(value: title) { OfflinePosterCard(title: title) }
                        .buttonStyle(.plain)
                        .contextMenu { deleteTitleButton(title) }
                }
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(filteredTitles) { title in
                    NavigationLink(value: title) { OfflineListRow(title: title) }
                        .buttonStyle(.plain)
                        .contextMenu { deleteTitleButton(title) }
                }
            }
        }
    }

    private func count(for filter: OfflineTypeFilter) -> Int {
        switch filter {
        case .all: store.titles.count
        case .movies: store.titles.filter(\.isMovie).count
        case .series: store.titles.filter { !$0.isMovie }.count
        }
    }

    private func viewButton(grid: Bool, icon: String) -> some View {
        Button { usesGrid = grid } label: {
            Image(systemName: icon).frame(width: 30, height: 28)
                .background(usesGrid == grid ? KinoPadTheme.gold.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(usesGrid == grid ? KinoPadTheme.gold : .secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func deleteTitleButton(_ title: OfflineTitle) -> some View {
        if store.deletableEpisodeCount(for: title) > 0 {
            Button(role: .destructive) {
                pendingTitleDeletion = title
            } label: {
                Label(title.isMovie ? "Удалить фильм с устройства" : "Удалить сериал с устройства", systemImage: "trash")
            }
        }
    }
}

private struct OfflinePosterCard: View {
    @EnvironmentObject private var progress: PlaybackProgressStore
    let title: OfflineTitle
    @ScaledMetric(relativeTo: .headline) private var titleSlotHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var subtitleSlotHeight: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var progressSlotHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .caption2) private var genresSlotHeight: CGFloat = 14

    private var watchedCount: Int { title.episodes.filter { progress.isWatched($0.progressKey) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                PosterImage(
                    url: title.posterURL,
                    placeholderSystemImage: title.isMovie ? "film.fill" : "tv.fill"
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.1)))

                Image(systemName: title.episodes.count == 1 ? "play.fill" : "list.bullet")
                    .font(.subheadline.bold()).foregroundStyle(.black)
                    .frame(width: 38, height: 38).background(KinoPadTheme.gold, in: Circle())
                    .padding(8)
            }
            Text(title.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: titleSlotHeight, maxHeight: titleSlotHeight, alignment: .topLeading)
            Text(title.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: subtitleSlotHeight, maxHeight: subtitleSlotHeight, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(watchedCount), total: Double(max(title.episodes.count, 1)))
                    .tint(KinoPadTheme.gold)
                Text(title.episodes.isEmpty ? " " : "Просмотрено \(watchedCount) из \(title.episodes.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(title.episodes.isEmpty ? 0 : 1)
            .frame(maxWidth: .infinity, minHeight: progressSlotHeight, maxHeight: progressSlotHeight, alignment: .topLeading)
            Text(title.genres.isEmpty ? " " : title.genres.prefix(2).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .opacity(title.genres.isEmpty ? 0 : 1)
                .frame(maxWidth: .infinity, minHeight: genresSlotHeight, maxHeight: genresSlotHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OfflineListRow: View {
    @EnvironmentObject private var progress: PlaybackProgressStore
    let title: OfflineTitle

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: title.posterURL)
            .frame(width: 64, height: 92).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(title.title).font(.headline)
                Text(title.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text("Просмотрено \(title.episodes.filter { progress.isWatched($0.progressKey) }.count) из \(title.episodes.count)")
                    .font(.caption).foregroundStyle(KinoPadTheme.gold)
            }
            Spacer()
            if title.totalBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: title.totalBytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(10).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SourceManagerView: View {
    @EnvironmentObject private var store: MediaLibraryStore
    @Environment(\.dismiss) private var dismiss
    @Binding var showsFolderImporter: Bool

    var body: some View {
        List {
            Section("Хранилища") {
                ForEach(store.sources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: source.isInternal ? AppDevice.storageSystemImage : "externaldrive")
                            .foregroundStyle(source.isAvailable ? KinoPadTheme.gold : .secondary)
                        VStack(alignment: .leading) {
                            Text(source.name)
                            if !source.isAvailable { Text("Носитель не подключён").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if !source.isInternal {
                            Button(role: .destructive) { store.removeSource(id: source.id) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showsFolderImporter = true }
                } label: {
                    Label("Подключить папку или внешний диск", systemImage: "externaldrive.badge.plus")
                }
            }
        }
        .navigationTitle("Папки и диски")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}

private struct OfflineSeasonSection: Identifiable {
    let season: Int
    let episodes: [OfflineEpisode]

    var id: Int { season }
    var title: String { season > 0 ? "Сезон \(season)" : "Без сезона" }
}

private struct MissingMediaSeasonSection: Identifiable {
    let season: Int
    let mediaItems: [PlayableMedia]

    var id: Int { season }
    var title: String { season > 0 ? "Сезон \(season)" : "Без сезона" }
}

private struct OfflineTitleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var store: MediaLibraryStore
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var session: KinoPubSession
    @EnvironmentObject private var downloads: OfflineDownloadManager
    let title: OfflineTitle

    @State private var remoteItem: CatalogItem?
    @State private var selectedPlayback: PlaybackSelection?
    @State private var downloadRequest: DownloadRequest?
    @State private var isChecking = false
    @State private var checkError: String?
    @State private var pendingEpisodeDeletion: OfflineEpisode?
    @State private var confirmsTitleDeletion = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var currentTitle: OfflineTitle {
        store.titles.first(where: { $0.id == title.id }) ?? title
    }

    private var missingMedia: [PlayableMedia] {
        guard let remoteItem else { return [] }
        let local = store.downloadedEpisodeKeys(for: remoteItem.id.value)
        return remoteItem.playableItems.filter { !local.contains("\($0.season):\($0.episode)") }
    }

    private var seasonSections: [OfflineSeasonSection] {
        Dictionary(grouping: currentTitle.episodes, by: \.season)
            .map { season, episodes in
                OfflineSeasonSection(
                    season: season,
                    episodes: episodes.sorted {
                        if $0.episode != $1.episode { return $0.episode < $1.episode }
                        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted { $0.season < $1.season }
    }

    private var missingSeasonSections: [MissingMediaSeasonSection] {
        Dictionary(grouping: missingMedia, by: \.season)
            .map { season, mediaItems in
                MissingMediaSeasonSection(
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
        List {
            Section {
                Group {
                    if isCompact {
                        VStack(alignment: .leading, spacing: 14) {
                            detailPoster.frame(maxWidth: .infinity)
                            detailMetadata
                        }
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            detailPoster
                            detailMetadata
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            if currentTitle.isMovie {
                Section("На диске") {
                    ForEach(currentTitle.episodes) { episode in
                        episodeRow(episode)
                    }
                }
            } else {
                ForEach(seasonSections) { section in
                    Section("\(section.title) · \(section.episodes.count) эп.") {
                        ForEach(section.episodes) { episode in
                            episodeRow(episode)
                        }
                    }
                }
            }

            if let remoteItem, !missingMedia.isEmpty {
                if missingMedia.contains(where: { $0.season > 0 }) {
                    ForEach(missingSeasonSections) { section in
                        Section {
                            ForEach(section.mediaItems) { media in
                                availableMediaRow(media, item: remoteItem)
                            }
                        } header: {
                            let downloadable = section.mediaItems.filter {
                                !downloads.isQueued(
                                    catalogID: remoteItem.id.value,
                                    season: $0.season,
                                    episode: $0.episode
                                )
                            }
                            availableSeasonHeader(
                                section: section,
                                item: remoteItem,
                                downloadable: downloadable
                            )
                        }
                    }
                } else {
                    Section("Доступно онлайн") {
                        ForEach(missingMedia) { media in
                            availableMediaRow(media, item: remoteItem)
                        }
                    }
                }
            }

            if let checkError { Section { Label(checkError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
        }
        .navigationTitle(currentTitle.title)
        .toolbar {
            if currentTitle.catalogID != nil {
                Button { Task { await checkForUpdates() } } label: { Label("Проверить серии", systemImage: "arrow.clockwise") }
            }
            if store.deletableEpisodeCount(for: currentTitle) > 0 {
                Button(role: .destructive) {
                    confirmsTitleDeletion = true
                } label: {
                    Label(currentTitle.isMovie ? "Удалить фильм" : "Удалить сериал", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .task { await checkForUpdates() }
        .fullScreenCover(item: $selectedPlayback) { selection in
            VideoPlayerScreen(
                url: selection.url,
                title: selection.title,
                compatibilityWarning: selection.warning,
                context: selection.context,
                audioTracks: selection.audioTracks,
                onClose: { selectedPlayback = nil }
            )
        }
        .sheet(item: $downloadRequest) { request in
            DownloadOptionsSheet(request: request)
        }
        .confirmationDialog(
            "Удалить \(currentTitle.isMovie ? "фильм" : "сериал") «\(currentTitle.title)» с \(AppDevice.platformName)?",
            isPresented: $confirmsTitleDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить с \(AppDevice.platformName)", role: .destructive) {
                if store.deleteFromDevice(title: currentTitle) {
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все скачанные файлы будут удалены без возможности отмены. Внешний диск не затрагивается.")
        }
        .confirmationDialog(
            pendingEpisodeDeletion.map { "Удалить \($0.displayNumber ?? $0.title)?" } ?? "Удалить видео?",
            isPresented: Binding(
                get: { pendingEpisodeDeletion != nil },
                set: { if !$0 { pendingEpisodeDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить с \(AppDevice.platformName)", role: .destructive) {
                if let episode = pendingEpisodeDeletion {
                    let shouldClose = currentTitle.episodes.count == 1
                    if store.deleteFromDevice(title: currentTitle, episode: episode), shouldClose {
                        dismiss()
                    }
                }
                pendingEpisodeDeletion = nil
            }
            Button("Отмена", role: .cancel) { pendingEpisodeDeletion = nil }
        } message: {
            Text("Файл эпизода будет удалён без возможности отмены.")
        }
    }

    private var detailPoster: some View {
        PosterImage(
            urls: [currentTitle.posterURL].compactMap { $0 } + (remoteItem?.posters?.candidateURLs ?? [])
        )
        .frame(width: isCompact ? 150 : 118, height: isCompact ? 225 : 177)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var detailMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentTitle.title).font(.title2.bold())
            Text(currentTitle.subtitle).foregroundStyle(.secondary)
            if let summary = currentTitle.summary ?? remoteItem?.plot {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(isCompact ? 8 : 5)
            }
            if isChecking {
                ProgressView("Проверяю новые серии…")
            } else if !missingMedia.isEmpty {
                Label("Доступно новых: \(missingMedia.count)", systemImage: "sparkles")
                    .foregroundStyle(KinoPadTheme.gold)
                Button {
                    if let remoteItem {
                        downloadRequest = DownloadRequest(item: remoteItem, mediaItems: missingMedia)
                    }
                } label: {
                    Label("Скачать новые серии", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: isCompact ? .infinity : 280)
            } else if remoteItem != nil {
                Label("Все доступные серии уже на диске", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let remoteItem {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        WatchLaterButton(item: remoteItem)
                        SubscriptionButton(item: remoteItem)
                    }
                    VStack(alignment: .leading) {
                        WatchLaterButton(item: remoteItem)
                        SubscriptionButton(item: remoteItem)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func availableSeasonHeader(
        section: MissingMediaSeasonSection,
        item: CatalogItem,
        downloadable: [PlayableMedia]
    ) -> some View {
        let title = Text("Доступно онлайн · \(section.title) · \(section.mediaItems.count) эп.")
        if isCompact {
            VStack(alignment: .leading, spacing: 6) {
                title
                availableSeasonDownloadControl(section: section, item: item, downloadable: downloadable)
            }
        } else {
            HStack {
                title
                Spacer()
                availableSeasonDownloadControl(section: section, item: item, downloadable: downloadable)
            }
        }
    }

    @ViewBuilder
    private func availableSeasonDownloadControl(
        section: MissingMediaSeasonSection,
        item: CatalogItem,
        downloadable: [PlayableMedia]
    ) -> some View {
        if downloadable.isEmpty {
            Label("В очереди", systemImage: "clock.fill")
                .foregroundStyle(.secondary)
        } else {
            Button {
                downloadRequest = DownloadRequest(
                    item: item,
                    mediaItems: downloadable,
                    title: "\(item.displayTitle) · \(section.title)",
                    allowsMediaSelection: true
                )
            } label: {
                Label("Скачать сезон", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderless)
        }
    }

    private func episodeRow(_ episode: OfflineEpisode) -> some View {
        let record = progress.record(for: episode.progressKey)
        return HStack(spacing: 12) {
            Button {
                guard let url = episode.url else { return }
                selectedPlayback = PlaybackSelection(
                    url: url, title: episode.title,
                    warning: episode.isSystemPlayable ? nil : "Формат \(url.pathExtension.uppercased()) пока не поддерживается системным плеером \(AppDevice.platformName).",
                    context: .offline(episode, catalogID: currentTitle.catalogID),
                    audioTracks: []
                )
            } label: {
                Image(systemName: episode.exists ? "play.circle.fill" : "exclamationmark.circle")
                    .font(.title2).foregroundStyle(episode.exists ? KinoPadTheme.gold : .red)
            }
            .buttonStyle(.plain).disabled(!episode.exists)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if let number = episode.displayNumber { Text(number).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Text(episode.title).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(episode.sourceName).lineLimit(1)
                    if let resolution = episode.resolution { Text(resolution) }
                    if let bytes = episode.byteCount { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
                }
                .font(.caption2).foregroundStyle(.secondary)
                if let record, !record.isWatched, record.fraction > 0 {
                    ProgressView(value: record.fraction).tint(KinoPadTheme.gold)
                }
            }
            Spacer()
            if store.canDeleteFromDevice(title: currentTitle, episode: episode) {
                Button(role: .destructive) {
                    pendingEpisodeDeletion = episode
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Удалить эпизод с устройства")
            }
            Button {
                progress.setWatched(!(record?.isWatched ?? false), key: episode.progressKey, duration: record?.duration)
            } label: {
                Image(systemName: record?.isWatched == true ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(record?.isWatched == true ? .green : .secondary)
            }
            .buttonStyle(.plain).accessibilityLabel(record?.isWatched == true ? "Отметить непросмотренным" : "Отметить просмотренным")
        }
        .padding(.vertical, 3)
    }

    private func availableMediaRow(_ media: PlayableMedia, item: CatalogItem) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedPlayback = PlaybackSelection(
                    url: media.manifestURL, title: media.title, warning: nil,
                    context: .online(catalogID: item.id.value, media: media),
                    audioTracks: media.audioTracks
                )
            } label: {
                Label(mediaLabel(media), systemImage: "play.circle.fill")
            }
            .buttonStyle(.plain)
            Spacer()
            if downloads.isQueued(catalogID: item.id.value, season: media.season, episode: media.episode) {
                ProgressView().controlSize(.small)
            } else {
                Button { downloadRequest = DownloadRequest(item: item, media: media) } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(KinoPadTheme.gold)
            }
        }
    }

    private func checkForUpdates() async {
        guard let catalogID = currentTitle.catalogID, session.isLoggedIn else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            remoteItem = try await session.details(for: catalogID)
            checkError = nil
        } catch {
            checkError = error.localizedDescription
        }
    }

    private func mediaLabel(_ media: PlayableMedia) -> String {
        media.season > 0 ? "S\(media.season) E\(media.episode) · \(media.title)" : media.title
    }
}

private struct PlaybackSelection: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let warning: String?
    let context: PlaybackContext
    let audioTracks: [CatalogAudio]
}
