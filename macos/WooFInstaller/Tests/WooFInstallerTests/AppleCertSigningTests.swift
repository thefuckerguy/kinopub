import Foundation
import Security
import XCTest
@testable import WooFInstaller

final class AppleCertSigningTests: XCTestCase {
    private let certificate = Data([1, 2, 3, 4])

    func testWildcardProfileDerivesConcreteEntitlements() throws {
        let profile = try makeProfile(applicationID: "TEAM123.app.xigua7648.*")
        try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: "DEVICE-1", certificate: certificate)
        let entitlements = try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)
        XCTAssertEqual(entitlements["application-identifier"] as? String, "TEAM123.app.xigua7648.gray5696")
        XCTAssertEqual(entitlements["keychain-access-groups"] as? [String], ["TEAM123.app.xigua7648.gray5696"])
        XCTAssertEqual(entitlements["get-task-allow"] as? Bool, false)
    }

    func testApplicationIdentifierPrefixIsIndependentFromTeamIdentifier() throws {
        let profile = try makeProfile(
            applicationID: "PREFIX99.app.xigua7648.*",
            teamID: "TEAM123",
            applicationIdentifierPrefixes: ["PREFIX99"],
            keychainGroups: ["PREFIX99.*", "PREFIX99.app.xigua7648.*"]
        )
        let entitlements = try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)
        XCTAssertEqual(entitlements["application-identifier"] as? String, "PREFIX99.app.xigua7648.gray5696")
        XCTAssertEqual(entitlements["keychain-access-groups"] as? [String], [
            "PREFIX99.app.xigua7648.gray5696",
            "PREFIX99.app.xigua7648.gray5696"
        ])
        XCTAssertEqual(entitlements["com.apple.developer.team-identifier"] as? String, "TEAM123")
    }

    func testGlobalWildcardProfileAllowsExpectedBundleID() throws {
        let profile = try makeProfile(
            applicationID: "PREFIX99.*",
            teamID: "TEAM123",
            applicationIdentifierPrefixes: ["PREFIX99"],
            keychainGroups: ["PREFIX99.*"]
        )
        let entitlements = try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)
        XCTAssertEqual(entitlements["application-identifier"] as? String, "PREFIX99.app.xigua7648.gray5696")
        XCTAssertEqual(entitlements["keychain-access-groups"] as? [String], ["PREFIX99.app.xigua7648.gray5696"])
    }

    func testExplicitProductionProfileMatchesProductionBundleID() throws {
        let profile = try makeProfile(
            applicationID: "L3J92GW97N.app.xigua7648.gray5696",
            teamID: "L3J92GW97N",
            applicationIdentifierPrefixes: ["L3J92GW97N"],
            keychainGroups: ["L3J92GW97N.app.xigua7648.gray5696"]
        )
        let entitlements = try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)
        XCTAssertEqual(entitlements["application-identifier"] as? String,
                       "L3J92GW97N.app.xigua7648.gray5696")
        XCTAssertEqual(entitlements["keychain-access-groups"] as? [String],
                       ["L3J92GW97N.app.xigua7648.gray5696"])
    }

    func testExplicitBundleMismatchDiagnosticShowsAllowedPattern() throws {
        let profile = try makeProfile(
            applicationID: "PREFIX99.app.kinopad.KinoPad",
            teamID: "TEAM123"
        )
        XCTAssertThrowsError(try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)) { error in
            guard case AppleCertError.incompatibleBundle = error else { return XCTFail("Wrong error: \(error)") }
            let diagnostic = error.localizedDescription
            XCTAssertTrue(diagnostic.contains("app.kinopad.KinoPad"))
            XCTAssertFalse(diagnostic.contains("DEVICE-1"))
            XCTAssertFalse(diagnostic.contains("01020304"))
        }
    }

    func testProfileRejectsWrongBundleDeviceCertificateAndExpiration() throws {
        let profile = try makeProfile(applicationID: "TEAM123.app.xigua7648.gray5696")
        XCTAssertThrowsError(try profile.entitlementsForBundle("another.bundle")) {
            guard case AppleCertError.incompatibleBundle = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertThrowsError(try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: "DEVICE-2", certificate: certificate)) {
            guard case AppleCertError.deviceNotProvisioned = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertThrowsError(try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: "DEVICE-1", certificate: Data([9]))) {
            guard case AppleCertError.certificateMismatch = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertThrowsError(try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: "DEVICE-1", certificate: certificate, now: Date().addingTimeInterval(7_200))) {
            guard case AppleCertError.expiredProfile = $0 else { return XCTFail("Wrong error: \($0)") }
        }
    }

    func testEnterpriseProfileSupportsAnyDevice() throws {
        let profile = try makeProfile(applicationID: "TEAM123.app.xigua7648.gray5696", allDevices: true)
        try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: "OTHER-DEVICE", certificate: certificate)
    }

    func testPKCS12ImportErrorsAreNotAllReportedAsWrongPassword() {
        guard case .cannotDecryptPKCS12(errSecAuthFailed) = AppleCertSigning.importError(for: errSecAuthFailed) else {
            return XCTFail("Authentication failure must be classified separately")
        }
        guard case .cannotDecryptPKCS12(errSecPkcs12VerifyFailure) = AppleCertSigning.importError(for: errSecPkcs12VerifyFailure) else {
            return XCTFail("MAC verification failure must be classified separately")
        }
        guard case .malformedPKCS12(errSecDecode) = AppleCertSigning.importError(for: errSecDecode) else {
            return XCTFail("Malformed input must not be called a wrong password")
        }
        guard case .malformedPKCS12(errSecUnsupportedFormat) = AppleCertSigning.importError(for: errSecUnsupportedFormat) else {
            return XCTFail("Unsupported input must not be called a wrong password")
        }
        guard case .pkcs12ImportFailed(errSecInvalidKeychain) = AppleCertSigning.importError(for: errSecInvalidKeychain) else {
            return XCTFail("Keychain failure must not be called a wrong password")
        }
    }

    func testIdentityCanFollowCertificateOnlyEntries() {
        let entries: [[String: Any]] = [
            [kSecImportItemCertChain as String: []],
            [kSecImportItemIdentity as String: "synthetic identity marker"]
        ]
        XCTAssertEqual(AppleCertSigning.identityEntryIndex(in: entries), 1)
        XCTAssertNil(AppleCertSigning.identityEntryIndex(in: [entries[0]]))
    }

    func testGeneratedPKCS12DistinguishesValidWrongPasswordAndMissingKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woof-p12-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let key = root.appendingPathComponent("key.pem")
        let certificate = root.appendingPathComponent("cert.pem")
        let identityP12 = root.appendingPathComponent("identity.p12")
        let certificateOnlyP12 = root.appendingPathComponent("certificate-only.p12")
        _ = try await ProcessRunner.checked("/usr/bin/openssl", [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key.path, "-out", certificate.path,
            "-days", "1", "-subj", "/CN=WooF Synthetic Test"
        ])
        try exportPKCS12(["pkcs12", "-export", "-inkey", key.path,
                          "-in", certificate.path, "-out", identityP12.path,
                          "-passout", "stdin"])
        try exportPKCS12(["pkcs12", "-export", "-nokeys", "-in", certificate.path,
                          "-out", certificateOnlyP12.path, "-passout", "stdin"])

        let identityData = try Data(contentsOf: identityP12)
        let importedCertificate = try AppleCertSigning.identityCertificate(p12: identityData, password: "fixture-secret")
        XCTAssertFalse(importedCertificate.isEmpty)
        let signingKeychain = try AppleCertSigning.createTemporaryKeychain(at: root.appendingPathComponent("signing.keychain-db"))
        defer { SecKeychainDelete(signingKeychain) }
        XCTAssertThrowsError(try AppleCertSigning.verifyImportedIdentity(certificate: importedCertificate, in: signingKeychain)) {
            guard case AppleCertError.signingIdentityNotFound = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        try AppleCertSigning.importIdentity(p12: identityData, password: "fixture-secret", into: signingKeychain)
        try AppleCertSigning.verifyImportedIdentity(certificate: importedCertificate, in: signingKeychain)
        XCTAssertThrowsError(try AppleCertSigning.verifyImportedIdentity(certificate: Data([0]), in: signingKeychain)) {
            guard case AppleCertError.signingIdentityNotFound = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        let originalSearchList = try AppleCertSigning.addToKeychainSearchList(signingKeychain)
        defer { SecKeychainSetSearchList(originalSearchList) }
        var activeSearchList: CFArray?
        XCTAssertEqual(SecKeychainCopySearchList(&activeSearchList), errSecSuccess)
        XCTAssertTrue((activeSearchList as? [SecKeychain])?.contains(where: { CFEqual($0, signingKeychain) }) == true)
        XCTAssertEqual(SecKeychainSetSearchList(originalSearchList), errSecSuccess)
        var restoredSearchList: CFArray?
        XCTAssertEqual(SecKeychainCopySearchList(&restoredSearchList), errSecSuccess)
        XCTAssertTrue(restoredSearchList.map { CFEqual($0, originalSearchList) } == true)
        XCTAssertThrowsError(try AppleCertSigning.identityCertificate(p12: identityData, password: "incorrect")) {
            guard case let AppleCertError.cannotDecryptPKCS12(status) = $0,
                  status == errSecAuthFailed || status == errSecPkcs12VerifyFailure else {
                return XCTFail("Wrong error: \($0)")
            }
        }
        XCTAssertThrowsError(try AppleCertSigning.identityCertificate(p12: Data("not-pkcs12".utf8), password: "fixture-secret")) {
            guard case AppleCertError.malformedPKCS12 = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertThrowsError(try AppleCertSigning.identityCertificate(p12: Data(contentsOf: certificateOnlyP12), password: "fixture-secret")) {
            guard case AppleCertError.missingPrivateKey = $0 else { return XCTFail("Wrong error: \($0)") }
        }
    }

    func testOpenSSL3NormalizationUsesNewPasswordAndCompatibleEnvelope() async throws {
        let openssl3 = "/opt/homebrew/opt/openssl@3/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: openssl3) else {
            throw XCTSkip("OpenSSL 3 is not installed at the supported Homebrew path")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("woof-modern-p12-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let key = root.appendingPathComponent("key.pem")
        let certificate = root.appendingPathComponent("cert.pem")
        let modernP12 = root.appendingPathComponent("modern.p12")
        let pbmacP12 = root.appendingPathComponent("pbmac.p12")
        _ = try await ProcessRunner.checked("/usr/bin/openssl", [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key.path, "-out", certificate.path,
            "-days", "1", "-subj", "/CN=WooF Modern Synthetic Test"
        ])
        try exportPKCS12(["pkcs12", "-export", "-inkey", key.path,
                          "-in", certificate.path, "-out", modernP12.path,
                          "-passout", "stdin"], executable: openssl3)
        try exportPKCS12(["pkcs12", "-export", "-inkey", key.path,
                          "-in", certificate.path, "-out", pbmacP12.path,
                          "-pbmac1_pbkdf2", "-passout", "stdin"], executable: openssl3)

        let modernData = try Data(contentsOf: modernP12)
        do {
            _ = try await AppleCertSigning.preparePKCS12(modernData, password: "incorrect")
            XCTFail("An incorrect password must not trigger a successful normalization")
        } catch AppleCertError.cannotDecryptPKCS12 {
            // Authentication failures must not be retried as format errors.
        }
        let normalized = try await AppleCertSigning.normalizePKCS12(modernData, password: "fixture-secret")
        XCTAssertNotEqual(normalized.password, "fixture-secret")
        XCTAssertNotEqual(normalized.p12, modernData)
        let normalizedURL = root.appendingPathComponent("normalized.p12")
        try normalized.p12.write(to: normalizedURL)
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: openssl3)
        verify.arguments = ["pkcs12", "-in", normalizedURL.path, "-noout", "-passin", "stdin"]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        let verifyInput = Pipe()
        verify.standardInput = verifyInput
        try verify.run()
        try verifyInput.fileHandleForWriting.write(contentsOf: Data((normalized.password + "\n").utf8))
        try verifyInput.fileHandleForWriting.close()
        verify.waitUntilExit()
        XCTAssertEqual(verify.terminationStatus, 0, "OpenSSL must accept the fresh internal password")
        let systemVerify = Process()
        systemVerify.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        systemVerify.arguments = ["pkcs12", "-in", normalizedURL.path, "-noout", "-passin", "stdin"]
        systemVerify.standardOutput = FileHandle.nullDevice
        systemVerify.standardError = FileHandle.nullDevice
        let systemInput = Pipe()
        systemVerify.standardInput = systemInput
        try systemVerify.run()
        try systemInput.fileHandleForWriting.write(contentsOf: Data((normalized.password + "\n").utf8))
        try systemInput.fileHandleForWriting.close()
        systemVerify.waitUntilExit()
        XCTAssertEqual(systemVerify.terminationStatus, 0, "LibreSSL must accept the fresh internal password")
        XCTAssertFalse(try AppleCertSigning.identityCertificate(p12: normalized.p12, password: normalized.password).isEmpty)

        let pbmacData = try Data(contentsOf: pbmacP12)
        do {
            _ = try AppleCertSigning.identityCertificate(p12: pbmacData, password: "fixture-secret")
            // Newer Security.framework versions can import PBMAC1 directly.
        } catch AppleCertError.cannotDecryptPKCS12, AppleCertError.malformedPKCS12 {
            // Security.framework can report an unsupported PBMAC1 envelope as either error.
            // Runtime fallback intentionally remains limited to malformed/unsupported errors,
            // so a genuinely incorrect password cannot be silently reinterpreted.
            let normalizedPBMAC = try await AppleCertSigning.normalizePKCS12(pbmacData, password: "fixture-secret")
            XCTAssertNotEqual(normalizedPBMAC.password, "fixture-secret")
            XCTAssertFalse(try AppleCertSigning.identityCertificate(p12: normalizedPBMAC.p12, password: normalizedPBMAC.password).isEmpty)
        }
    }

    private func exportPKCS12(_ arguments: [String], executable: String = "/usr/bin/openssl") throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        process.standardInput = input
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("fixture-secret\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AppleCertSigningTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Synthetic PKCS#12 export failed"])
        }
    }

    private func makeProfile(
        applicationID: String,
        allDevices: Bool = false,
        teamID: String = "TEAM123",
        applicationIdentifierPrefixes: [String]? = nil,
        keychainGroups: [String]? = nil
    ) throws -> AppleCertProfile {
        var plist: [String: Any] = [
            "Name": "Test Profile",
            "ExpirationDate": Date().addingTimeInterval(3_600),
            "TeamIdentifier": [teamID],
            "DeveloperCertificates": [certificate],
            "ProvisionedDevices": ["DEVICE-1"],
            "ProvisionsAllDevices": allDevices,
            "Entitlements": [
                "application-identifier": applicationID,
                "keychain-access-groups": keychainGroups ?? ["TEAM123.*"],
                "get-task-allow": false
            ] as [String: Any]
        ]
        if let applicationIdentifierPrefixes {
            plist["ApplicationIdentifierPrefix"] = applicationIdentifierPrefixes
        }
        return try AppleCertProfile(plist: plist)
    }
}
