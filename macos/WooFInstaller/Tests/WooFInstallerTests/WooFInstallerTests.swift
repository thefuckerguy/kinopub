import XCTest
@testable import WooFInstaller

final class WooFInstallerTests: XCTestCase {
    func testDeviceListDecodesConnectedPhysicalDevice() throws {
        let json = #"""
        {
          "result": {
            "devices": [{
              "identifier": "core-device-id",
              "visibilityClass": "default",
              "properties": {
                "hardware": {
                  "marketingName": "iPhone 17 Pro",
                  "platform": "iOS",
                  "productType": "iPhone18,1",
                  "udid": "PHONE-UDID"
                },
                "software": {"osVersionNumber": {"stringValue": "26.0"}},
                "state": {
                  "name": "Телефон",
                  "developerModeStatus": {"enabled": {"mode": 1}}
                },
                "connection": {"state": "connected", "transportType": "usb"}
              }
            }]
          }
        }
        """#
        let document = try JSONDecoder().decode(DeviceListDocument.self, from: Data(json.utf8))
        let device = try XCTUnwrap(document.result.devices.first?.installerDevice)
        XCTAssertEqual(device.id, "PHONE-UDID")
        XCTAssertEqual(device.name, "Телефон")
        XCTAssertTrue(device.developerModeEnabled)
    }

    func testSimulatorsAndDisconnectedDevicesAreIgnored() throws {
        let json = #"""
        {
          "result": {
            "devices": [{
              "identifier": "simulator",
              "visibilityClass": "simulators",
              "properties": {
                "hardware": {"platform": "iOS"},
                "software": {},
                "state": {},
                "connection": {"state": "connected"}
              }
            }, {
              "identifier": "phone",
              "visibilityClass": "default",
              "properties": {
                "hardware": {"platform": "iOS"},
                "software": {},
                "state": {},
                "connection": {"state": "disconnected"}
              }
            }]
          }
        }
        """#
        let document = try JSONDecoder().decode(DeviceListDocument.self, from: Data(json.utf8))
        XCTAssertTrue(document.result.devices.compactMap(\.installerDevice).isEmpty)
    }

    func testVersionComparisonHandlesDifferentComponentCounts() {
        XCTAssertLessThan(AppVersion("v0.3.6"), AppVersion("0.4.0"))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        XCTAssertFalse(AppVersion("2.0") < AppVersion("1.9.9"))
    }

    func testReleaseSelectsIPAAsset() throws {
        let json = #"""
        {
          "tag_name": "v0.4.0",
          "name": "WooF.Play 0.4.0",
          "html_url": "https://github.com/thefuckerguy/kinopub/releases/tag/v0.4.0",
          "draft": false,
          "prerelease": false,
          "assets": [{
            "name": "WooF.Play.ipa",
            "size": 123,
            "browser_download_url": "https://github.com/thefuckerguy/kinopub/releases/download/v0.4.0/WooF.Play.ipa",
            "digest": "sha256:abc"
          }]
        }
        """#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.ipaAsset?.name, "WooF.Play.ipa")
    }

    func testProvisioningMembershipIsEnforced() {
        let inspection = IPAInspection(
            displayName: "WooF.Play",
            bundleID: InstallerConstants.expectedBundleID,
            version: "0.3.6",
            build: "10",
            teamName: "Team",
            expirationDate: Date().addingTimeInterval(3600),
            provisionedDevices: ["ALLOWED"],
            provisionsAllDevices: false
        )
        XCTAssertTrue(inspection.supports(deviceID: "ALLOWED"))
        XCTAssertFalse(inspection.supports(deviceID: "OTHER"))
    }

    func testCurrentDevelopmentIPAHasValidSignatureAndMetadata() async throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryRoot = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ipaURL = repositoryRoot
            .appendingPathComponent("ios/build/installer/WooF.Play-0.3.7-development.ipa")
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw XCTSkip("Локальный development IPA отсутствует.")
        }

        let prepared = try await IPAInspector.prepare(ipaURL)
        defer { prepared.removeTemporaryFiles() }
        XCTAssertEqual(prepared.inspection.bundleID, InstallerConstants.expectedBundleID)
        XCTAssertEqual(prepared.inspection.version, "0.3.7")
        XCTAssertFalse(prepared.inspection.provisionedDevices.isEmpty)
    }

    func testPasscodeProtectedDeveloperModeMessageKeepsSecurityEnabled() {
        let message = InstallerError.developerModePasscodeProtected.localizedDescription
        XCTAssertTrue(message.contains("Не отключайте код‑пароль"))
        XCTAssertTrue(message.contains("Конфиденциальность и безопасность"))
    }
}
