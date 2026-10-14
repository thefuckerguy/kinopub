import Darwin
import XCTest
@testable import WooFInstaller

final class AltStoreTransferTests: XCTestCase {
    private let container = "/private/var/mobile/Containers/Data/Application/51F27D28-6A6C-4C11-B53C-2D18F6CEBD58"
    private let resignedBundle = "com.P4R7L5C576.com.rileytestut.AltStore"

    private func app(bundle: String? = nil, version: String? = "2.3", accessible: Bool? = true,
                     path: String? = nil) -> InstalledApp {
        InstalledApp(bundleIdentifier: bundle ?? resignedBundle, version: version, bundleVersion: "64",
                     containerAccessible: accessible, dataContainerPath: path ?? container)
    }

    func testDetectsCurrentTeamPrefixAndLegacyClassicBundleIDs() throws {
        for bundle in [resignedBundle, "com.rileytestut.AltStore",
                       "com.rileytestut.AltStore.P4R7L5C576", "com.rileytestut.AltStore.Beta",
                       "com.P4R7L5C576.com.rileytestut.AltStore.Beta"] {
            let installation = try AltStoreInstallation.detect(in: [app(bundle: bundle)])
            XCTAssertEqual(installation.bundleID, bundle)
            XCTAssertEqual(installation.version, "2.3")
        }
    }

    func testPALSideStoreAndSimilarNamesAreNotClassic() {
        for bundle in ["io.altstore.AltStore", "com.SideStore.SideStore",
                       "org.attacker.com.rileytestut.AltStore", "com.bad.com.rileytestut.AltStore",
                       "com.rileytestut.AltStore.NotClassic", "com.rileytestut.AltStore.BetaExtra",
                       "com.P4R7L5C576..com.rileytestut.AltStore"] {
            XCTAssertFalse(AltStoreInstallation.isClassicBundleID(bundle), bundle)
            XCTAssertThrowsError(try AltStoreInstallation.detect(in: [app(bundle: bundle)]))
        }
        XCTAssertThrowsError(try AltStoreInstallation.detect(in: []))
    }

    func testAmbiguousCopiesAreRejectedWithoutGuessing() {
        XCTAssertThrowsError(try AltStoreInstallation.detect(in: [app(), app(bundle: "com.rileytestut.AltStore.Beta")])) {
            XCTAssertEqual($0.localizedDescription, AltStoreTransferError.ambiguousInstallation.localizedDescription)
        }
    }

    func testRequiresExplicitContainerAccess() {
        for accessible: Bool? in [false, nil] {
            XCTAssertThrowsError(try AltStoreInstallation.detect(in: [app(accessible: accessible)]))
        }
        let missing = InstalledApp(bundleIdentifier: resignedBundle, version: "2.3", bundleVersion: "64",
                                   containerAccessible: true, dataContainerPath: nil)
        XCTAssertThrowsError(try AltStoreInstallation.detect(in: [missing]))
    }

    func testRejectsInvalidContainerRootsTraversalAndURLSyntax() throws {
        for path in ["", "file://" + container, "/tmp/AltStore", container + "/../Other",
                     container + "/", container + "?query", container + "#fragment",
                     "/private/var/mobile/Containers/Data/Application/not-a-uuid",
                     "/private/var/mobile/Containers/Data/Application/../../Other"] {
            XCTAssertThrowsError(try AltStoreInstallation.detect(in: [app(path: path)]), path)
        }
        XCTAssertNoThrow(try AltStoreInstallation.detect(in: [app(path: String(container.dropFirst(8)))]))
    }

    func testDecodesActualDeviceContainerFieldsAndKeepsOldAppJSONCompatible() throws {
        let json = #"""
        {"result":{"apps":[{"bundleIdentifier":"com.P4R7L5C576.com.rileytestut.AltStore",
        "version":"2.3","bundleVersion":"64","containerAccessible":true,
        "dataContainerPath":"/private/var/mobile/Containers/Data/Application/51F27D28-6A6C-4C11-B53C-2D18F6CEBD58"},
        {"bundleIdentifier":"app.xigua7648.gray5696","version":"0.3.9"}]}}
        """#
        let document = try JSONDecoder().decode(InstalledAppsDocument.self, from: Data(json.utf8))
        XCTAssertEqual(try AltStoreInstallation.detect(in: document.result.apps).bundleID, resignedBundle)
        XCTAssertNil(document.result.apps[1].containerAccessible)
        XCTAssertNil(document.result.apps[1].dataContainerPath)
    }

    func testCommandsTargetExactPairedDeviceAndPrivateAppFile() throws {
        let installation = try AltStoreInstallation.detect(in: [app()])
        let source = URL(fileURLWithPath: "/tmp/A file & name.ipa")
        XCTAssertEqual(installation.copyArguments(deviceID: "PHONE", source: source), [
            "devicectl", "device", "copy", "to", "--device", "PHONE", "--source", source.path,
            "--domain-type", "appDataContainer", "--domain-identifier", resignedBundle,
            "--destination", "tmp/WooFInstaller/WooF.Play.ipa", "--timeout", "120"
        ])
        XCTAssertEqual(installation.importURL.absoluteString, "file://" + container + "/tmp/WooFInstaller/WooF.Play.ipa")
        XCTAssertEqual(installation.handoffURL.absoluteString,
                       "altstore-classic://install?url=file%3A%2F%2F%2Fprivate%2Fvar%2Fmobile%2FContainers%2FData%2FApplication%2F51F27D28-6A6C-4C11-B53C-2D18F6CEBD58%2Ftmp%2FWooFInstaller%2FWooF.Play.ipa")
        XCTAssertEqual(installation.launchArguments(deviceID: "PHONE"), [
            "devicectl", "device", "process", "launch", "--device", "PHONE",
            "--terminate-existing", "--payload-url", installation.handoffURL.absoluteString,
            "--timeout", "30", resignedBundle
        ])
        XCTAssertTrue(installation.importURL.isFileURL)
        XCTAssertEqual(installation.importURL.pathExtension, "ipa")
    }

    func testUsesLegacyAltStoreSchemeBelowVersion22() throws {
        for version in ["2.1.9", "1.7"] {
            let installation = try AltStoreInstallation.detect(in: [app(version: version)])
            XCTAssertTrue(installation.handoffURL.absoluteString.hasPrefix("altstore://install?url="))
            XCTAssertTrue(installation.handoffURL.absoluteString.contains("file%3A%2F%2F"))
        }
        let unknown = try AltStoreInstallation.detect(in: [app(version: nil)])
        XCTAssertTrue(unknown.handoffURL.absoluteString.hasPrefix("altstore-classic://install?url="))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("woof-altstore-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testSnapshotIsIndependentPrivateAndRemovedAfterUse() throws {
        let source = try temporaryDirectory().appendingPathComponent("Input.ipa")
        let original = Data(repeating: 0x41, count: 90_000)
        try original.write(to: source)
        let snapshot = try AltStoreIPASnapshot.create(from: source)
        defer { snapshot.remove() }
        try Data("changed".utf8).write(to: source)
        XCTAssertEqual(try Data(contentsOf: snapshot.url), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: snapshot.directory.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: snapshot.url.path)[.posixPermissions] as? Int, 0o600)
        snapshot.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSnapshotRejectsSymlinksEmptyDirectoriesAndSpecialFiles() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("Input.ipa")
        try Data("IPA".utf8).write(to: source)
        let link = directory.appendingPathComponent("Link.ipa")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try AltStoreIPASnapshot.create(from: link))
        let empty = directory.appendingPathComponent("Empty.ipa")
        try Data().write(to: empty)
        XCTAssertThrowsError(try AltStoreIPASnapshot.create(from: empty))
        let folder = directory.appendingPathComponent("Folder.ipa")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertThrowsError(try AltStoreIPASnapshot.create(from: folder))
        let fifo = directory.appendingPathComponent("FIFO.ipa")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try AltStoreIPASnapshot.create(from: fifo))
    }

    func testSnapshotRejectsOversizeBeforeCopying() throws {
        let source = try temporaryDirectory().appendingPathComponent("Huge.ipa")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: source)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(AltStoreIPASnapshot.maximumFileBytes + 1))
        XCTAssertThrowsError(try AltStoreIPASnapshot.create(from: source))
    }

    func testFailedCopyDoesNotLaunchAltStoreAndFailedLaunchIsNotSuccess() async throws {
        let installation = try AltStoreInstallation.detect(in: [app()])
        let device = IOSDevice(id: "PHONE", name: "iPhone", model: "iPhone", osVersion: "26",
                               connection: "USB", developerModeEnabled: true)
        let snapshot = AltStoreIPASnapshot(url: URL(fileURLWithPath: "/tmp/fixture/WooF.Play.ipa"))
        var calls = 0
        do {
            try await AltStoreTransfer.send(snapshot: snapshot, to: device, installation: installation) { _, _ in
                calls += 1
                return CommandResult(status: 1, data: Data("copy failed".utf8))
            }
            XCTFail("Copy failure must stop the handoff")
        } catch { XCTAssertEqual(calls, 1) }
        calls = 0
        do {
            try await AltStoreTransfer.send(snapshot: snapshot, to: device, installation: installation) { _, _ in
                calls += 1
                return CommandResult(status: calls == 1 ? 0 : 1, data: Data())
            }
            XCTFail("Launch failure must not report success")
        } catch {
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(error.localizedDescription, AltStoreTransferError.launchFailed.localizedDescription)
        }
    }
}
