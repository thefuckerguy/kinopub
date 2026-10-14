import XCTest
import zlib
@testable import WooFInstaller

final class AltServerTests: XCTestCase {
    func testDownloadsAreRestrictedToOfficialHTTPSFeedAndReleasePaths() throws {
        XCTAssertTrue(AltServerPolicy.allows(AltServerPolicy.feedURL))
        XCTAssertTrue(AltServerPolicy.allows(AltServerPolicy.downloadURL))
        XCTAssertTrue(AltServerPolicy.allows(URL(string: "https://cdn.altstore.io/file/altstore/altserver/1_8_1.zip")!))
        for raw in ["http://cdn.altstore.io/file/altstore/altserver.zip",
                    "https://cdn.altstore.io.evil.test/file/altstore/altserver.zip",
                    "https://evil.test/altserver.zip", "https://user@cdn.altstore.io/file/altstore/altserver.zip",
                    "https://cdn.altstore.io:8443/file/altstore/altserver.zip",
                    "https://cdn.altstore.io/file/altstore/altserver/1_8.zip?redirect=evil",
                    "https://cdn.altstore.io/file/altstore/altserver/../evil.zip",
                    "https://cdn.altstore.io/file/altstore/other.zip"] {
            XCTAssertFalse(AltServerPolicy.allows(try XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testFeedSelectsNewestReleaseAndIgnoresUntrustedURLs() throws {
        let xml = #"""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><enclosure url="https://cdn.altstore.io/file/altstore/altserver/1_8.zip" sparkle:version="97" sparkle:shortVersionString="1.8" /></item>
        <item><enclosure url="https://evil.test/evil.zip" sparkle:version="999" sparkle:shortVersionString="99.0" /></item>
        <item><enclosure url="https://cdn.altstore.io/file/altstore/altserver/1_8_1.zip" sparkle:version="98" sparkle:shortVersionString="1.8.1" /></item>
        </channel></rss>
        """#
        XCTAssertEqual(try AltServerFeed.latestURL(in: Data(xml.utf8)).lastPathComponent, "1_8_1.zip")
        XCTAssertThrowsError(try AltServerFeed.latestURL(in: Data("<rss/>".utf8)))
        XCTAssertThrowsError(try AltServerFeed.latestURL(in: Data("<rss>".utf8)))
    }

    func testVersionComparisonDoesNotDowngradeInstalledAltServer() {
        let url = URL(fileURLWithPath: "/Applications/AltServer.app")
        let old = AltServerInstallation(appURL: url, version: "1.8", build: "97")
        let new = AltServerInstallation(appURL: url, version: "1.8.1", build: "98")
        XCTAssertTrue(old.isOlder(than: new))
        XCTAssertFalse(new.isOlder(than: old))
        XCTAssertFalse(new.isOlder(than: new))
        XCTAssertTrue(new.isOlder(than: AltServerInstallation(appURL: url, version: "1.8.1", build: "99")))
    }

    func testArchiveAcceptsContainedFrameworkLinks() throws {
        let archive = zip([
            ("AltServer.app/Contents/Info.plist", "plist", 0o100644),
            ("AltServer.app/Contents/Frameworks/A.framework/Versions/Current", "A", 0o120755),
            ("AltServer.app/Contents/Frameworks/A.framework/A", "Versions/Current/A", 0o120755),
            ("AltServer.app/Contents/Frameworks/A.framework/Versions/A/A", "binary", 0o100755)
        ])
        XCTAssertNoThrow(try SafeAltServerArchive.validate(archive))
    }

    func testArchiveRejectsTraversalAbsoluteAndUnexpectedPaths() {
        for path in ["../outside", "/Applications/evil.app", "AltServer.app/../../outside",
                     "AltServer.app\\..\\outside", "AltServer.app/./file", "Other.app/Contents/Info.plist"] {
            XCTAssertThrowsError(try SafeAltServerArchive.validate(zip([
                ("AltServer.app/Contents/Info.plist", "plist", 0o100644), (path, "bad", 0o100644)
            ])), path)
        }
    }

    func testArchiveRejectsEscapingLinksAndWritesThroughLinks() {
        for target in ["../../outside", "/tmp/outside", "..", "Versions/../outside"] {
            XCTAssertThrowsError(try SafeAltServerArchive.validate(zip([
                ("AltServer.app/Contents/Info.plist", "plist", 0o100644),
                ("AltServer.app/Contents/link", target, 0o120755)
            ])), target)
        }
        XCTAssertThrowsError(try SafeAltServerArchive.validate(zip([
            ("AltServer.app/Contents/Info.plist", "plist", 0o100644),
            ("AltServer.app/Contents/link", "safe", 0o120755),
            ("AltServer.app/Contents/link/file", "bad", 0o100644)
        ])))
    }

    func testArchiveRejectsDuplicateNamesTruncationAndLocalHeaderMismatch() {
        let valid = zip([("AltServer.app/Contents/Info.plist", "plist", 0o100644)])
        XCTAssertThrowsError(try SafeAltServerArchive.validate(Data(valid.dropLast())))
        var mismatch = valid
        mismatch[30] = UInt8(ascii: "X")
        XCTAssertThrowsError(try SafeAltServerArchive.validate(mismatch))
        XCTAssertThrowsError(try SafeAltServerArchive.validate(zip([
            ("AltServer.app/Contents/Info.plist", "plist", 0o100644),
            ("AltServer.app/Contents/info.plist", "other", 0o100644)
        ])))
    }

    func testDeflatedArchiveRejectsForgedCentralAndLocalSizesBeforeExtraction() throws {
        let entries = [("AltServer.app/Contents/Info.plist", String(repeating: "A", count: 1_048_576), 0o100644)]
        // A real DEFLATE stream produces 1 MiB; only the central directory claims one byte.
        XCTAssertThrowsError(try SafeAltServerArchive.validate(zip(entries, deflated: true, centralSize: 1)))
        // Even agreeing forged headers cannot hide the actual decoded output length.
        XCTAssertThrowsError(try SafeAltServerArchive.validate(zip(entries, deflated: true, centralSize: 1, localSize: 1)))
        XCTAssertNoThrow(try SafeAltServerArchive.validate(zip(entries, deflated: true)))
    }

    func testArchiveRejectsCRCDisagreementAndCorruptPayload() {
        let valid = zip([("AltServer.app/Contents/Info.plist", "plist", 0o100644)])
        var wrongLocalCRC = valid
        wrongLocalCRC[14] ^= 0xff
        XCTAssertThrowsError(try SafeAltServerArchive.validate(wrongLocalCRC))
        var corruptPayload = valid
        corruptPayload[30 + "AltServer.app/Contents/Info.plist".utf8.count] ^= 0xff
        XCTAssertThrowsError(try SafeAltServerArchive.validate(corruptPayload))
    }

    @MainActor
    func testUnsignedOrWrongBundleCannotPassValidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woof-altserver-test-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for bundleID in ["evil.AltServer", AltServerPolicy.bundleID] {
            let info = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": "1.8", "CFBundleVersion": "97"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            do {
                _ = try await AltServerSetup.validate(contents.deletingLastPathComponent())
                XCTFail("Unsigned/wrong identity app passed validation")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("подписи"))
            }
        }
    }

    /// Optional deterministic integration check against a separately downloaded official fixture.
    @MainActor
    func testOfficialArchiveFixtureAndSignatureWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["ALT_SERVER_TEST_ARCHIVE"] else {
            throw XCTSkip("Set ALT_SERVER_TEST_ARCHIVE to an official ZIP for archive/signature integration QA.")
        }
        let archiveURL = URL(fileURLWithPath: path)
        try SafeAltServerArchive.validate(Data(contentsOf: archiveURL))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woof-altserver-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await ProcessRunner.checked("/usr/bin/tar", ["-xf", archiveURL.path, "-C", root.path,
                                                                  "--no-same-owner", "--no-same-permissions"])
        let installation = try await AltServerSetup.validate(root.appendingPathComponent("AltServer.app"))
        XCTAssertFalse(installation.version.isEmpty)
    }

    private func zip(_ entries: [(String, String, Int)], deflated: Bool = false,
                     centralSize: Int? = nil, localSize: Int? = nil) -> Data {
        var result = Data()
        var central = Data()
        func bytes(_ number: Int, _ width: Int) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) })
        }
        for (path, value, mode) in entries {
            let name = Data(path.utf8)
            let content = Data(value.utf8)
            let checksum = content.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count)) }
            var payload = content
            if deflated {
                var compressedLength = compressBound(uLong(content.count))
                var compressed = Data(count: Int(compressedLength))
                let status = compressed.withUnsafeMutableBytes { output in
                    content.withUnsafeBytes { input in
                        compress2(output.bindMemory(to: Bytef.self).baseAddress!, &compressedLength,
                                  input.bindMemory(to: Bytef.self).baseAddress!, uLong(content.count), Z_BEST_COMPRESSION)
                    }
                }
                XCTAssertEqual(status, Z_OK)
                // ZIP method 8 stores raw DEFLATE: remove the zlib header and Adler-32 trailer.
                payload = compressed.subdata(in: 2..<(Int(compressedLength) - 4))
            }
            let offset = result.count
            let localParts = [bytes(0x04034b50, 4), bytes(20, 2), bytes(0, 2), bytes(deflated ? 8 : 0, 2),
                              bytes(0, 4), bytes(Int(checksum), 4), bytes(payload.count, 4),
                              bytes(localSize ?? content.count, 4), bytes(name.count, 2), bytes(0, 2), name, payload]
            for part in localParts { result.append(part) }
            let centralParts = [bytes(0x02014b50, 4), bytes(0x0314, 2), bytes(20, 2), bytes(0, 2), bytes(deflated ? 8 : 0, 2),
                                bytes(0, 4), bytes(Int(checksum), 4), bytes(payload.count, 4),
                                bytes(centralSize ?? content.count, 4), bytes(name.count, 2), Data(repeating: 0, count: 8),
                                bytes(mode << 16, 4), bytes(offset, 4), name]
            for part in centralParts { central.append(part) }
        }
        let centralOffset = result.count
        result += central
        let endParts = [bytes(0x06054b50, 4), Data(repeating: 0, count: 4), bytes(entries.count, 2),
                        bytes(entries.count, 2), bytes(central.count, 4), bytes(centralOffset, 4), bytes(0, 2)]
        for part in endParts { result.append(part) }
        return result
    }
}
