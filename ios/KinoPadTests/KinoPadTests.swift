import XCTest
@testable import KinoPad

final class KinoPadTests: XCTestCase {
    func testProvisioningProfileParserAndRemainingTime() throws {
        let expirationDate = Date(timeIntervalSince1970: 2_000_100_000)
        let plist: [String: Any] = [
            "ExpirationDate": expirationDate,
            "ProvisionedDevices": ["PHONE-UDID"]
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        var wrappedData = Data("CMS-prefix".utf8)
        wrappedData.append(plistData)
        wrappedData.append(Data("CMS-suffix".utf8))

        let profile = try XCTUnwrap(ProvisioningProfileInfo.decode(data: wrappedData))
        XCTAssertEqual(profile.expirationDate, expirationDate)
        XCTAssertEqual(profile.provisionedDevices, ["PHONE-UDID"])
        XCTAssertTrue(profile.isLocallyProvisioned)
        XCTAssertEqual(
            ProvisioningProfileInfo.remainingText(
                until: expirationDate,
                now: expirationDate.addingTimeInterval(-(90_061))
            ),
            "1 д. 1 ч. 1 мин."
        )
        XCTAssertEqual(
            ProvisioningProfileInfo.remainingText(until: expirationDate, now: expirationDate),
            "Срок истёк"
        )
    }

    func testFlexibleIDDecodesNumberAndString() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(FlexibleID.self, from: Data("42".utf8)).value, "42")
        XCTAssertEqual(try decoder.decode(FlexibleID.self, from: Data("\"abc\"".utf8)).value, "abc")
    }

    func testFlexibleBoolDecodesAPIRepresentations() throws {
        let decoder = JSONDecoder()
        XCTAssertTrue(try decoder.decode(FlexibleBool.self, from: Data("1".utf8)).value)
        XCTAssertFalse(try decoder.decode(FlexibleBool.self, from: Data("0".utf8)).value)
        XCTAssertTrue(try decoder.decode(FlexibleBool.self, from: Data("\"true\"".utf8)).value)
    }

    func testBestManifestPrefersHighestResolutionAndH264() throws {
        let data = Data(
            """
            {
              "id": 1,
              "title": "Movie",
              "videos": [{
                "number": 1,
                "files": [
                  {"codec":"hevc","h":2160,"url":{"hls4":"https://example.com/hevc.m3u8","http":"https://example.com/hevc.mp4"}},
                  {"codec":"h264","h":2160,"url":{"hls4":"https://example.com/avc.m3u8","http":"https://example.com/avc.mp4"}},
                  {"codec":"h264","h":1080,"url":{"hls4":"https://example.com/1080.m3u8"}}
                ]
              }]
            }
            """.utf8
        )
        let item = try JSONDecoder().decode(CatalogItem.self, from: data)
        XCTAssertEqual(item.playableItems.first?.manifestURL.absoluteString, "https://example.com/avc.m3u8")
        XCTAssertEqual(item.playableItems.first?.downloadVariants.count, 3)
        XCTAssertEqual(item.playableItems.first?.downloadVariants.first?.displayName, "2160p · H264")
        XCTAssertEqual(item.playableItems.first?.downloadVariants.first?.directFileURL?.absoluteString, "https://example.com/avc.mp4")
    }

    func testMediaExtensionClassification() {
        let mp4 = MediaFile(url: URL(fileURLWithPath: "/tmp/movie.MP4"), byteCount: nil, modifiedAt: nil)
        let mkv = MediaFile(url: URL(fileURLWithPath: "/tmp/movie.mkv"), byteCount: nil, modifiedAt: nil)
        XCTAssertTrue(mp4.isSystemPlayable)
        XCTAssertFalse(mkv.isSystemPlayable)
        XCTAssertTrue(MediaScanner.supportedExtensions.contains(mkv.fileExtension))
    }

    func testMediaNameParserRecognizesSeasonAndEpisode() {
        let parsed = MediaNameParser.parse(url: URL(fileURLWithPath: "/Disk/Grimsburg/Grimsburg.S02E09.1080p.mkv"))
        XCTAssertEqual(parsed.title, "Grimsburg")
        XCTAssertEqual(parsed.season, 2)
        XCTAssertEqual(parsed.episode, 9)
    }

    func testPCStateReconnectsLegacyPathsToExternalFilesWithoutDuplicateTitle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinoPadExternal-\(UUID().uuidString)", isDirectory: true)
        let seriesFolder = root.appendingPathComponent("Гримсбург", isDirectory: true)
        let firstEpisode = seriesFolder.appendingPathComponent("Grimsburg.S01E01.1080p.mp4")
        let secondEpisode = seriesFolder.appendingPathComponent("Grimsburg.S02E03.1080p.mp4")
        try FileManager.default.createDirectory(at: seriesFolder, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: firstEpisode.path, contents: Data("one".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondEpisode.path, contents: Data("two".utf8)))
        defer { try? FileManager.default.removeItem(at: root) }

        let state: [String: Any] = [
            "series": 4242,
            "metadata": [
                "title": "Гримсбург",
                "original_title": "Grimsburg",
                "poster_url": "https://example.com/grimsburg.jpg",
                "type": "serial",
                "genres": ["Комедия"]
            ],
            "completed": [
                "1:1": [
                    "season": 1,
                    "episode": 1,
                    "path": "/Users/old/Shows/Grimsburg/Grimsburg.S01E01.1080p.mp4",
                    "title": "Episode 1"
                ],
                "2:3": [
                    "season": 2,
                    "episode": 3,
                    "path": #"D:\Shows\Grimsburg\Season 2\Grimsburg.S02E03.1080p.mp4"#,
                    "title": "Episode 3"
                ]
            ]
        ]
        let stateData = try JSONSerialization.data(withJSONObject: state)
        try stateData.write(to: seriesFolder.appendingPathComponent(".kinopub-state.json"))

        let result = MediaScanner.scan(
            sources: [MediaSource(id: UUID(), name: "Внешний диск", url: root, isInternal: false)],
            downloadedAssets: []
        )

        let title = try XCTUnwrap(result.titles.first)
        XCTAssertEqual(result.titles.count, 1)
        XCTAssertEqual(title.catalogID, "4242")
        XCTAssertEqual(title.title, "Гримсбург")
        XCTAssertEqual(title.seasonCount, 2)
        XCTAssertEqual(title.availableCount, 2)
        XCTAssertEqual(title.episodes.compactMap(\.url).count, 2)
    }

    func testAutomaticWatchedThreshold() {
        XCTAssertFalse(PlaybackProgressStore.shouldAutomaticallyMarkWatched(position: 800, duration: 1_000))
        XCTAssertTrue(PlaybackProgressStore.shouldAutomaticallyMarkWatched(position: 900, duration: 1_000))
        XCTAssertTrue(PlaybackProgressStore.shouldAutomaticallyMarkWatched(position: 3_500, duration: 3_600))
    }

    func testCatalogPageDecodesPaginationAndFindsNextPage() throws {
        let data = Data(
            """
            {
              "items": [{"id": 1, "title": "One"}],
              "pagination": {"total": 4, "current": 2, "perpage": 40, "total_items": 121}
            }
            """.utf8
        )
        let page = try JSONDecoder().decode(CatalogPage.self, from: data)
        XCTAssertEqual(page.pagination?.current, 2)
        XCTAssertEqual(page.pagination?.total, 4)
        XCTAssertTrue(page.hasPage(after: 2, requestedPageSize: 40))

        let lastPageData = Data(
            """
            {
              "items": [{"id": 2, "title": "Last"}],
              "pagination": {"total": 4, "current": 4, "perpage": 40, "total_items": 121}
            }
            """.utf8
        )
        let lastPage = try JSONDecoder().decode(CatalogPage.self, from: lastPageData)
        XCTAssertFalse(lastPage.hasPage(after: 4, requestedPageSize: 40))
    }

    func testPosterURLsNormalizeAndRequestUsesKinoWatchReferer() throws {
        let posters = Posters(
            small: "//cdn.example.com/small.jpg",
            medium: nil,
            big: "http://cdn.example.com/big.jpg",
            wide: nil
        )
        XCTAssertEqual(posters.candidateURLs.first?.absoluteString, "https://cdn.example.com/big.jpg")
        XCTAssertTrue(posters.candidateURLs.contains(URL(string: "https://cdn.example.com/small.jpg")!))

        let request = PosterImageRequestFactory.makeRequest(for: posters.candidateURLs[0])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://kino.watch/")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
    }

    func testPlayableMediaCarriesVoiceoverNames() throws {
        let data = Data(
            """
            {
              "id": 5,
              "title": "Series",
              "seasons": [{
                "number": 1,
                "episodes": [{
                  "number": 2,
                  "files": [{"h":1080,"url":{"hls4":"https://example.com/master.m3u8"}}],
                  "audios": [{
                    "id": 9,
                    "index": 1,
                    "lang": "rus",
                    "type": {"title": "дубляж"},
                    "author": {"title": "LostFilm"}
                  }]
                }]
              }]
            }
            """.utf8
        )
        let item = try JSONDecoder().decode(CatalogItem.self, from: data)
        XCTAssertEqual(item.playableItems.first?.audioTracks.first?.displayName, "LostFilm · дубляж")
    }

    func testSeasonDownloadRequestKeepsDistinctSelectableEpisodes() throws {
        let data = Data(
            """
            {
              "id": 55,
              "title": "Series",
              "seasons": [{
                "number": 2,
                "episodes": [
                  {"number": 1, "files": [{"h":1080,"url":{"hls4":"https://example.com/s2e1.m3u8"}}]},
                  {"number": 2, "files": [{"h":1080,"url":{"hls4":"https://example.com/s2e2.m3u8"}}]}
                ]
              }]
            }
            """.utf8
        )
        let item = try JSONDecoder().decode(CatalogItem.self, from: data)
        let request = DownloadRequest(
            item: item,
            mediaItems: item.playableItems,
            title: "Series · Сезон 2",
            allowsMediaSelection: true
        )

        XCTAssertTrue(request.allowsMediaSelection)
        XCTAssertEqual(request.title, "Series · Сезон 2")
        XCTAssertEqual(request.candidates.count, 2)
        XCTAssertEqual(Set(request.candidates.map(\.id)).count, 2)
    }

    func testPersonalMirrorInstallerAcceptsOnlyDifferentHTTPSOrigin() throws {
        XCTAssertNil(normalizedMirrorOrigin(from: URL(string: "http://mirror.example/path")!))
        XCTAssertNil(normalizedMirrorOrigin(from: URL(string: "https://mos-gorsud.site/user/login")!))
        XCTAssertNil(normalizedMirrorOrigin(from: URL(string: "https://auth.mos-gorsud.site/redirect")!))

        let mirror = try XCTUnwrap(
            normalizedMirrorOrigin(from: URL(string: "https://my.personal-mirror.example/item/view/42?q=1")!)
        )
        XCTAssertEqual(mirror.absoluteString, "https://my.personal-mirror.example")
    }

    func testSafeDeviceOverviewProtectsFiveRecentlyActiveSlots() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let activeDevices = (1...5).map { index in
            KinoPubDevice(
                id: String(index),
                title: "Device \(index)",
                hardware: nil,
                software: nil,
                isBrowser: false,
                createdAt: nil,
                updatedAt: nil,
                lastSeen: now.addingTimeInterval(-Double(index * 60))
            )
        }
        let busy = KinoPubDeviceOverview(devices: activeDevices, currentDeviceID: "1")
        XCTAssertEqual(busy.activeCount(at: now), 5)
        XCTAssertEqual(busy.freeSlotCount, 0)
        XCTAssertTrue(busy.allSlotsRecentlyActive(at: now))

        let stale = KinoPubDevice(
            id: "5",
            title: "Old device",
            hardware: nil,
            software: nil,
            isBrowser: false,
            createdAt: nil,
            updatedAt: nil,
            lastSeen: now.addingTimeInterval(-(KinoPubDeviceOverview.activityWindow + 1))
        )
        let removable = KinoPubDeviceOverview(devices: Array(activeDevices.dropLast()) + [stale], currentDeviceID: "1")
        XCTAssertEqual(removable.activeCount(at: now), 4)
        XCTAssertEqual(removable.safelyRemovableCount(at: now), 1)
        XCTAssertFalse(removable.allSlotsRecentlyActive(at: now))

        let unknown = KinoPubDevice(
            id: "unknown",
            title: "Unknown device",
            hardware: nil,
            software: nil,
            isBrowser: false,
            createdAt: nil,
            updatedAt: nil,
            lastSeen: nil
        )
        XCTAssertFalse(unknown.isSafelyRemovable(at: now))

        let browser = KinoPubDevice(
            id: "browser",
            title: "Safari",
            hardware: nil,
            software: nil,
            isBrowser: true,
            createdAt: nil,
            updatedAt: nil,
            lastSeen: now
        )
        let withBrowser = KinoPubDeviceOverview(devices: activeDevices + [browser], currentDeviceID: "1")
        XCTAssertEqual(withBrowser.slotDevices.count, 5)
        XCTAssertEqual(withBrowser.browserCount, 1)
        XCTAssertEqual(withBrowser.activeCount(at: now), 5)
        XCTAssertEqual(withBrowser.freeSlotCount, 0)
        XCTAssertTrue(withBrowser.allSlotsRecentlyActive(at: now))
        XCTAssertFalse(browser.isSafelyRemovable(at: now))
    }

    func testOfflineAssetLocationRecoversNoFollowAndOldContainerPath() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinoPadTests-\(UUID().uuidString)", isDirectory: true)
        let asset = home
            .appendingPathComponent("Library/com.apple.UserManagedAssets.test", isDirectory: true)
            .appendingPathComponent("Episode.movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let legacy = "/.nofollow/private/var/mobile/Containers/Data/Application/OLD/Library/com.apple.UserManagedAssets.test/Episode.movpkg"
        XCTAssertEqual(
            OfflineAssetLocation.resolve(storedPath: legacy, homeDirectory: home)?.standardizedFileURL,
            asset.standardizedFileURL
        )
        XCTAssertEqual(
            OfflineAssetLocation.persistedPath(for: URL(fileURLWithPath: legacy), homeDirectory: home),
            "Library/com.apple.UserManagedAssets.test/Episode.movpkg"
        )
    }

    func testDeviceMediaOwnershipRejectsSiblingAndSymlinkEscape() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinoPadOwnership-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Movies", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        let inside = root.appendingPathComponent("Movie.mp4")
        let link = root.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: inside.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: base) }

        XCTAssertTrue(DeviceMediaOwnership.contains(inside, within: root))
        XCTAssertFalse(DeviceMediaOwnership.contains(outside, within: root))
        XCTAssertFalse(DeviceMediaOwnership.contains(link.appendingPathComponent("Other.mp4"), within: root))
    }

    @MainActor
    func testDeletingDownloadedEpisodeRemovesFileAndRecord() throws {
        let suite = "KinoPadDeleteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MediaLibraryStore(defaults: defaults)
        let assetID = UUID()
        let package = store.internalFolderURL
            .appendingPathComponent("DeleteTest-\(assetID.uuidString).movpkg", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: package) }

        let record = OfflineAssetRecord(
            id: assetID,
            catalogID: "delete-test",
            title: "Delete Test",
            originalTitle: nil,
            posterURL: nil,
            type: "serial",
            genres: [],
            season: 1,
            episode: 2,
            episodeTitle: "Episode 2",
            localURL: OfflineAssetLocation.persistedPath(for: package),
            downloadedAt: Date()
        )
        store.registerDownloadedAsset(record)
        let episode = OfflineEpisode(
            id: "download:\(assetID.uuidString)",
            url: package,
            season: 1,
            episode: 2,
            title: "Episode 2",
            byteCount: nil,
            modifiedAt: Date(),
            resolution: nil,
            sourceName: "На iPad",
            isSystemPlayable: true
        )
        let title = OfflineTitle(
            id: "catalog:delete-test",
            catalogID: "delete-test",
            title: "Delete Test",
            originalTitle: nil,
            summary: nil,
            posterURL: nil,
            type: "serial",
            genres: [],
            updatedAt: Date(),
            episodes: [episode]
        )

        XCTAssertTrue(store.canDeleteFromDevice(title: title, episode: episode))
        XCTAssertTrue(store.deleteFromDevice(title: title, episode: episode))
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.path))
        XCTAssertFalse(store.downloadedAssets.contains(where: { $0.id == assetID }))
    }

    @MainActor
    func testPlaybackPositionPersistsForResume() throws {
        let suite = "KinoPadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let context = PlaybackContext(
            key: "online:42:1:3",
            catalogID: "42",
            season: 1,
            episode: 3,
            initialPosition: nil,
            initialDuration: 1_800
        )
        let firstStore = PlaybackProgressStore(defaults: defaults)
        firstStore.update(key: context.key, position: 321, duration: 1_800)

        let restoredStore = PlaybackProgressStore(defaults: defaults)
        XCTAssertEqual(restoredStore.resumePosition(for: context), 321, accuracy: 0.001)
    }

    @MainActor
    func testWatchLaterPersistsAndTogglesByCatalogID() throws {
        let suite = "KinoPadWatchLaterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = try JSONDecoder().decode(
            CatalogItem.self,
            from: Data(#"{"id":77,"title":"Watch Later"}"#.utf8)
        )

        let first = WatchLaterStore(defaults: defaults)
        XCTAssertTrue(first.toggle(item))
        XCTAssertTrue(first.contains(item))

        let restored = WatchLaterStore(defaults: defaults)
        XCTAssertTrue(restored.contains(id: "77"))
        XCTAssertFalse(restored.toggle(item))

        let removed = WatchLaterStore(defaults: defaults)
        XCTAssertTrue(removed.items.isEmpty)
    }

    @MainActor
    func testPersonalViewingPersistsOnlyInItsLocalStore() throws {
        let suite = "KinoPadPersonalViewingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = try JSONDecoder().decode(
            CatalogItem.self,
            from: Data(#"{"id":88,"title":"Private title","type":"serial"}"#.utf8)
        )

        let first = PersonalViewingStore(defaults: defaults)
        XCTAssertTrue(first.toggle(item))
        XCTAssertTrue(first.contains(id: "88"))

        let restored = PersonalViewingStore(defaults: defaults)
        XCTAssertEqual(restored.items.map { $0.id.value }, ["88"])
        XCTAssertFalse(restored.toggle(item))

        let removed = PersonalViewingStore(defaults: defaults)
        XCTAssertTrue(removed.items.isEmpty)
    }
}
