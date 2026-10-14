import CryptoKit
import Foundation
import Security

enum AppleCertError: LocalizedError {
    case cannotDecryptPKCS12(OSStatus)
    case passwordRequired
    case malformedPKCS12(OSStatus)
    case missingPrivateKey
    case pkcs12ImportFailed(OSStatus)
    case normalizationToolUnavailable
    case normalizationFailed(String)
    case invalidProfile
    case expiredProfile
    case incompatibleBundle(String)
    case deviceNotProvisioned
    case certificateMismatch
    case missingCredentials
    case keychainFailure(OSStatus)
    case signingIdentityNotFound
    case signingIdentityAccessDenied(OSStatus)
    case signingIdentityNotEligible
    case unsupportedNestedBundle(String)
    case invalidApp
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .cannotDecryptPKCS12(status): return "Не удалось расшифровать .p12 (код \(status)): пароль не подошёл или файл повреждён. Проверьте файл и пароль."
        case .passwordRequired: return "Для открытия .p12 требуется пароль. Введите пароль файла сертификата."
        case let .malformedPKCS12(status): return "Формат .p12 повреждён или не поддерживается macOS (код \(status)). Экспортируйте сертификат с закрытым ключом заново."
        case .missingPrivateKey: return "В .p12 не найден сертификат вместе с закрытым ключом. Экспортируйте из AppleCert именно identity с закрытым ключом."
        case let .pkcs12ImportFailed(status): return "macOS не смогла импортировать .p12 (код \(status)). Проверьте сертификат и доступ к связке ключей."
        case .normalizationToolUnavailable: return "Для этого формата .p12 нужен OpenSSL 3. Установите пакет openssl@3 через Homebrew и повторите добавление сертификата."
        case let .normalizationFailed(stage): return "Не удалось преобразовать .p12 в совместимый с macOS формат (\(stage)). Проверьте файл и пароль или экспортируйте сертификат заново."
        case .invalidProfile: return "Не удалось прочитать provisioning profile или в нём нет обязательных данных для подписи."
        case .expiredProfile: return "Срок действия AppleCert provisioning profile истёк. Добавьте новый профиль."
        case let .incompatibleBundle(pattern): return "AppleCert профиль не разрешает приложение. Разрешённый bundle pattern: \(pattern). Выберите подходящий профиль."
        case .deviceNotProvisioned: return "Выбранного устройства нет в AppleCert provisioning profile. Обновите профиль с UDID этого устройства."
        case .certificateMismatch: return "Сертификат из .p12 отсутствует в выбранном provisioning profile."
        case .missingCredentials: return "Не удалось прочитать сохранённые AppleCert данные. Добавьте сертификат заново."
        case let .keychainFailure(status): return "Ошибка macOS Keychain (\(status)). Проверьте доступ к связке ключей."
        case .signingIdentityNotFound: return "Сертификат с закрытым ключом не найден во временной связке ключей для подписи. Добавьте AppleCert сертификат заново."
        case let .signingIdentityAccessDenied(status): return "Нет доступа к закрытому ключу AppleCert во временной связке ключей (код \(status)). Проверьте разрешения Keychain и повторите попытку."
        case .signingIdentityNotEligible: return "Импортированный AppleCert сертификат не распознаётся macOS как действительный сертификат для подписи кода. Проверьте сертификат и его срок действия."
        case let .unsupportedNestedBundle(id): return "В сборке есть вложенное приложение \(id), для которого выбранный профиль не подходит."
        case .invalidApp: return "Не удалось найти корректный пакет WooF.Play после сборки."
        case let .signingFailed(reason): return "Не удалось подписать WooF.Play сохранённым сертификатом: \(reason)"
        }
    }
}

struct AppleCertProfile {
    let name: String
    let teamID: String
    let expirationDate: Date
    let devices: Set<String>
    let provisionsAllDevices: Bool
    let certificateData: [Data]
    let entitlements: [String: Any]
    let applicationIdentifierPrefix: String
    let applicationIdentifierPattern: String

    init(plist: [String: Any]) throws {
        guard let name = plist["Name"] as? String,
              let expiration = plist["ExpirationDate"] as? Date,
              let teamID = (plist["TeamIdentifier"] as? [String])?.first,
              let entitlements = plist["Entitlements"] as? [String: Any],
              let applicationID = entitlements["application-identifier"] as? String,
              let certificates = plist["DeveloperCertificates"] as? [Data],
              !certificates.isEmpty else { throw AppleCertError.invalidProfile }
        let declaredPrefixes = plist["ApplicationIdentifierPrefix"] as? [String] ?? []
        let prefix = declaredPrefixes
            .filter { applicationID.hasPrefix("\($0).") }
            .max(by: { $0.count < $1.count })
            ?? String(applicationID.prefix(while: { $0 != "." }))
        guard !prefix.isEmpty,
              applicationID.hasPrefix("\(prefix).") else { throw AppleCertError.invalidProfile }
        self.name = name
        self.teamID = teamID
        self.expirationDate = expiration
        self.devices = Set(plist["ProvisionedDevices"] as? [String] ?? [])
        self.provisionsAllDevices = plist["ProvisionsAllDevices"] as? Bool ?? false
        self.certificateData = certificates
        self.entitlements = entitlements
        self.applicationIdentifierPrefix = prefix
        self.applicationIdentifierPattern = String(applicationID.dropFirst(prefix.count + 1))
    }

    func validate(bundleID: String, deviceID: String, certificate: Data, now: Date = Date()) throws {
        guard expirationDate > now else { throw AppleCertError.expiredProfile }
        guard provisionsAllDevices || devices.contains(deviceID) else { throw AppleCertError.deviceNotProvisioned }
        guard certificateData.contains(certificate) else { throw AppleCertError.certificateMismatch }
        _ = try entitlementsForBundle(bundleID)
    }

    func entitlementsForBundle(_ bundleID: String) throws -> [String: Any] {
        guard Self.matches(applicationIdentifierPattern, value: bundleID) else {
            throw AppleCertError.incompatibleBundle(applicationIdentifierPattern)
        }
        var result = entitlements
        result["application-identifier"] = "\(applicationIdentifierPrefix).\(bundleID)"
        result["com.apple.developer.team-identifier"] = teamID
        if let groups = entitlements["keychain-access-groups"] as? [String] {
            result["keychain-access-groups"] = try groups.map { group in
                guard group.hasPrefix("\(applicationIdentifierPrefix).") else { return group }
                let groupPattern = String(group.dropFirst(applicationIdentifierPrefix.count + 1))
                guard Self.matches(groupPattern, value: bundleID) else {
                    if groupPattern.hasSuffix("*") {
                        throw AppleCertError.incompatibleBundle(groupPattern)
                    }
                    return group
                }
                return "\(applicationIdentifierPrefix).\(bundleID)"
            }
        }
        return result
    }

    private static func matches(_ pattern: String, value: String) -> Bool {
        if pattern.hasSuffix("*") { return value.hasPrefix(String(pattern.dropLast())) }
        return pattern == value
    }
}

struct AppleCertStatus {
    let profileName: String
    let expirationDate: Date
    let teamID: String
}

struct AppleCertMaterial {
    let p12: Data
    let password: String
    let certificate: Data
}

enum AppleCertSigning {
    private static let service = "app.kinopad.WooFInstaller.AppleCert"
    private static let account = "p12-password"
    private static let activeIDKey = "appleCertCredentialID"

    static var isConfigured: Bool { UserDefaults.standard.string(forKey: activeIDKey) != nil }

    static func status() async throws -> AppleCertStatus? {
        guard isConfigured else { return nil }
        let profile = try await loadProfile()
        _ = try loadPassword()
        return AppleCertStatus(profileName: profile.name, expirationDate: profile.expirationDate, teamID: profile.teamID)
    }

    static func configure(p12URL: URL, password: String, profileURL: URL) async throws -> AppleCertStatus {
        let sourceP12 = try Data(contentsOf: p12URL)
        let material = try await preparePKCS12(sourceP12, password: password)
        let profileData = try Data(contentsOf: profileURL)
        let directory = try credentialsDirectory()
        let newID = UUID().uuidString
        let newDirectory = directory.appendingPathComponent(newID, isDirectory: true)
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try material.p12.write(to: newDirectory.appendingPathComponent("identity.p12"), options: .atomic)
            let savedProfileURL = newDirectory.appendingPathComponent("profile.mobileprovision")
            try profileData.write(to: savedProfileURL, options: .atomic)
            for name in ["identity.p12", "profile.mobileprovision"] {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: newDirectory.appendingPathComponent(name).path)
            }
            let profile = try await decodeProfile(at: savedProfileURL)
            guard profile.expirationDate > Date() else { throw AppleCertError.expiredProfile }
            guard profile.certificateData.contains(material.certificate) else { throw AppleCertError.certificateMismatch }
            _ = try profile.entitlementsForBundle(InstallerConstants.expectedBundleID)
            try savePassword(material.password)
            let oldID = UserDefaults.standard.string(forKey: activeIDKey)
            UserDefaults.standard.set(newID, forKey: activeIDKey)
            if let oldID { try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldID)) }
            return AppleCertStatus(profileName: profile.name, expirationDate: profile.expirationDate, teamID: profile.teamID)
        } catch {
            try? FileManager.default.removeItem(at: newDirectory)
            throw error
        }
    }

    static func remove() throws {
        let oldID = UserDefaults.standard.string(forKey: activeIDKey)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppleCertError.keychainFailure(status) }
        if let oldID {
            let oldDirectory = try credentialsDirectory().appendingPathComponent(oldID)
            if FileManager.default.fileExists(atPath: oldDirectory.path) {
                try FileManager.default.removeItem(at: oldDirectory)
            }
        }
        UserDefaults.standard.removeObject(forKey: activeIDKey)
    }

    static func signAndPackage(appURL: URL, deviceID: String) async throws -> URL {
        guard try appBundleID(appURL) == InstallerConstants.expectedBundleID else { throw AppleCertError.invalidApp }
        let p12 = try Data(contentsOf: credentialURL("identity.p12"))
        let password = try loadPassword()
        let profileURL = try credentialURL("profile.mobileprovision")
        let profile = try await decodeProfile(at: profileURL)
        let certificate = try identityCertificate(p12: p12, password: password)
        try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: deviceID, certificate: certificate)

        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("woof-sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let keychainURL = temporaryRoot.appendingPathComponent("signing.keychain-db")
        let keychain = try createTemporaryKeychain(at: keychainURL)
        defer { SecKeychainDelete(keychain) }
        try importIdentity(p12: p12, password: password, into: keychain)
        let identityHash = Insecure.SHA1.hash(data: certificate).map { String(format: "%02X", $0) }.joined()
        let originalSearchList = try addToKeychainSearchList(keychain)
        var searchListRestored = false
        defer {
            if !searchListRestored { _ = SecKeychainSetSearchList(originalSearchList) }
        }
        try verifyImportedIdentity(certificate: certificate, in: keychain)
        try await verifyCodesignEligibility(identityHash: identityHash, keychainURL: keychainURL)

        let bundles = try nestedCode(in: appURL)
        for bundle in bundles {
            let kind = bundle.pathExtension.lowercased()
            if kind == "app" || kind == "appex" {
                let bundleID = try appBundleID(bundle)
                do { _ = try profile.entitlementsForBundle(bundleID) }
                catch { throw AppleCertError.unsupportedNestedBundle(bundleID) }
                try await signBundle(bundle, bundleID: bundleID, profileURL: profileURL, profile: profile, keychainURL: keychainURL, identityHash: identityHash, temporaryRoot: temporaryRoot)
            } else {
                _ = try await checkedCodesign(["--force", "--sign", identityHash, "--keychain", keychainURL.path, "--timestamp=none", bundle.path])
            }
        }
        try await signBundle(appURL, bundleID: InstallerConstants.expectedBundleID, profileURL: profileURL, profile: profile, keychainURL: keychainURL, identityHash: identityHash, temporaryRoot: temporaryRoot)
        _ = try await checkedCodesign(["--verify", "--deep", "--strict", appURL.path])
        let restoreStatus = SecKeychainSetSearchList(originalSearchList)
        guard restoreStatus == errSecSuccess else { throw AppleCertError.keychainFailure(restoreStatus) }
        searchListRestored = true

        let payload = temporaryRoot.appendingPathComponent("Payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: appURL, to: payload.appendingPathComponent(appURL.lastPathComponent))
        let destinationDirectory = try signedIPADirectory()
        let destination = destinationDirectory.appendingPathComponent("WooF.Play-\(UUID().uuidString).ipa")
        do {
            _ = try await ProcessRunner.checked("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", payload.path, destination.path])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            let prepared = try await IPAInspector.prepare(destination)
            defer { prepared.removeTemporaryFiles() }
            guard prepared.inspection.bundleID == InstallerConstants.expectedBundleID,
                  prepared.inspection.supports(deviceID: deviceID) else { throw AppleCertError.invalidProfile }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func validateSaved(for deviceID: String) async throws {
        let profile = try await loadProfile()
        let p12 = try Data(contentsOf: credentialURL("identity.p12"))
        let certificate = try identityCertificate(p12: p12, password: loadPassword())
        try profile.validate(bundleID: InstallerConstants.expectedBundleID, deviceID: deviceID, certificate: certificate)
    }

    private static func signBundle(_ url: URL, bundleID: String, profileURL: URL, profile: AppleCertProfile, keychainURL: URL, identityHash: String, temporaryRoot: URL) async throws {
        let embeddedProfile = url.appendingPathComponent("embedded.mobileprovision")
        if FileManager.default.fileExists(atPath: embeddedProfile.path) {
            try FileManager.default.removeItem(at: embeddedProfile)
        }
        try FileManager.default.copyItem(at: profileURL, to: embeddedProfile)
        let entitlements = try profile.entitlementsForBundle(bundleID)
        let entitlementURL = temporaryRoot.appendingPathComponent("entitlements-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
        try data.write(to: entitlementURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: entitlementURL) }
        _ = try await checkedCodesign(["--force", "--sign", identityHash, "--keychain", keychainURL.path, "--timestamp=none", "--generate-entitlement-der", "--entitlements", entitlementURL.path, url.path])
    }

    private static func checkedCodesign(_ arguments: [String]) async throws -> CommandResult {
        do { return try await ProcessRunner.checked("/usr/bin/codesign", arguments) }
        catch { throw AppleCertError.signingFailed(String(error.localizedDescription.prefix(600))) }
    }

    private static func nestedCode(in appURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased()
            if ["framework", "appex", "app", "xpc"].contains(ext) && values.isDirectory == true {
                result.append(url)
            } else if ext == "dylib" && values.isDirectory == false {
                result.append(url)
            }
        }
        return result.sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    private static func appBundleID(_ url: URL) throws -> String {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String else { throw AppleCertError.invalidApp }
        return id
    }

    private static func decodeProfile(at url: URL) async throws -> AppleCertProfile {
        let result = try await ProcessRunner.checked("/usr/bin/security", ["cms", "-D", "-i", url.path])
        guard let plist = try PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any] else { throw AppleCertError.invalidProfile }
        return try AppleCertProfile(plist: plist)
    }

    static func identityCertificate(p12: Data, password: String) throws -> Data {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("woof-cert-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let keychain = try createTemporaryKeychain(at: temporaryRoot.appendingPathComponent("check.keychain-db"))
        defer { SecKeychainDelete(keychain) }
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password,
                                      kSecImportExportKeychain as String: keychain]
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else { throw importError(for: status) }
        guard let identity = firstIdentity(in: items) else { throw AppleCertError.missingPrivateKey }
        var certificate: SecCertificate?
        let copyStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard copyStatus == errSecSuccess, let certificate else { throw AppleCertError.keychainFailure(copyStatus) }
        return SecCertificateCopyData(certificate) as Data
    }

    static func createTemporaryKeychain(at url: URL) throws -> SecKeychain {
        var bytes = [UInt8](repeating: 0, count: 32)
        defer { for index in bytes.indices { bytes[index] = 0 } }
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppleCertError.keychainFailure(errSecInternalComponent) }
        var keychain: SecKeychain?
        let status = bytes.withUnsafeBytes { buffer in
            SecKeychainCreate(url.path, UInt32(buffer.count), buffer.baseAddress, false, nil, &keychain)
        }
        guard status == errSecSuccess, let keychain else { throw AppleCertError.keychainFailure(status) }
        let unlockStatus = bytes.withUnsafeBytes { buffer in
            SecKeychainUnlock(keychain, UInt32(buffer.count), buffer.baseAddress, true)
        }
        guard unlockStatus == errSecSuccess else {
            SecKeychainDelete(keychain)
            throw AppleCertError.keychainFailure(unlockStatus)
        }
        return keychain
    }

    static func importIdentity(p12: Data, password: String, into keychain: SecKeychain) throws {
        var trustedApp: SecTrustedApplication?
        let trustStatus = SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &trustedApp)
        guard trustStatus == errSecSuccess, let trustedApp else { throw AppleCertError.keychainFailure(trustStatus) }
        var access: SecAccess?
        let accessStatus = SecAccessCreate("WooF Installer signing" as CFString, [trustedApp] as CFArray, &access)
        guard accessStatus == errSecSuccess, let access else { throw AppleCertError.keychainFailure(accessStatus) }
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password,
                                      kSecImportExportKeychain as String: keychain,
                                      kSecImportExportAccess as String: access]
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else { throw importError(for: status) }
        guard firstIdentity(in: items) != nil else { throw AppleCertError.missingPrivateKey }
    }

    static func addToKeychainSearchList(_ keychain: SecKeychain) throws -> CFArray {
        var currentList: CFArray?
        let copyStatus = SecKeychainCopySearchList(&currentList)
        guard copyStatus == errSecSuccess, let currentList,
              let keychains = currentList as? [SecKeychain] else {
            throw AppleCertError.keychainFailure(copyStatus == errSecSuccess ? errSecInternalComponent : copyStatus)
        }
        let updateStatus = SecKeychainSetSearchList((keychains + [keychain]) as CFArray)
        guard updateStatus == errSecSuccess else {
            _ = SecKeychainSetSearchList(currentList)
            throw AppleCertError.keychainFailure(updateStatus)
        }
        return currentList
    }

    static func verifyImportedIdentity(certificate: Data, in keychain: SecKeychain) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassIdentity,
                                    kSecMatchSearchList as String: [keychain],
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnRef as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw AppleCertError.signingIdentityNotFound }
        guard status == errSecSuccess else { throw AppleCertError.signingIdentityAccessDenied(status) }
        guard let identities = result as? [SecIdentity] else { throw AppleCertError.signingIdentityNotFound }
        for identity in identities {
            var foundCertificate: SecCertificate?
            let certificateStatus = SecIdentityCopyCertificate(identity, &foundCertificate)
            guard certificateStatus == errSecSuccess, let foundCertificate else {
                throw AppleCertError.signingIdentityAccessDenied(certificateStatus)
            }
            guard SecCertificateCopyData(foundCertificate) as Data == certificate else { continue }
            var privateKey: SecKey?
            let keyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
            guard keyStatus == errSecSuccess, privateKey != nil else {
                throw AppleCertError.signingIdentityAccessDenied(keyStatus)
            }
            return
        }
        throw AppleCertError.signingIdentityNotFound
    }

    private static func verifyCodesignEligibility(identityHash: String, keychainURL: URL) async throws {
        let result = try await ProcessRunner.checked("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning", keychainURL.path])
        guard result.output.localizedCaseInsensitiveContains(identityHash) else {
            throw AppleCertError.signingIdentityNotEligible
        }
    }

    static func firstIdentity(in items: CFArray?) -> SecIdentity? {
        guard let entries = items as? [[String: Any]],
              let index = identityEntryIndex(in: entries),
              let value = entries[index][kSecImportItemIdentity as String] else { return nil }
        return (value as! SecIdentity)
    }

    static func identityEntryIndex(in entries: [[String: Any]]) -> Int? {
        entries.firstIndex { $0[kSecImportItemIdentity as String] != nil }
    }

    static func importError(for status: OSStatus) -> AppleCertError {
        switch status {
        case errSecAuthFailed, errSecPkcs12VerifyFailure:
            return .cannotDecryptPKCS12(status)
        case errSecPassphraseRequired:
            return .passwordRequired
        case errSecDecode, errSecUnknownFormat, errSecUnsupportedFormat:
            return .malformedPKCS12(status)
        default:
            return .pkcs12ImportFailed(status)
        }
    }

    static func preparePKCS12(_ source: Data, password: String) async throws -> AppleCertMaterial {
        do {
            let certificate = try identityCertificate(p12: source, password: password)
            return AppleCertMaterial(p12: source, password: password, certificate: certificate)
        } catch AppleCertError.malformedPKCS12 {
            let normalized = try await normalizePKCS12(source, password: password)
            let certificate = try identityCertificate(p12: normalized.p12, password: normalized.password)
            return AppleCertMaterial(p12: normalized.p12, password: normalized.password, certificate: certificate)
        }
    }

    static func normalizePKCS12(_ source: Data, password: String) async throws -> (p12: Data, password: String) {
        guard source.count <= 32 * 1024 * 1024 else { throw AppleCertError.normalizationFailed("слишком большой файл") }
        let openssl = try await openssl3URL()
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let root = fileManager.temporaryDirectory.appendingPathComponent("woof-p12-normalize-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            defer { try? fileManager.removeItem(at: root) }
            let sourceURL = root.appendingPathComponent("source.p12")
            let certificatesURL = root.appendingPathComponent("certificates.pem")
            let passwordURL = root.appendingPathComponent("internal-password.txt")
            let outputURL = root.appendingPathComponent("normalized.p12")
            try writePrivateFile(source, at: sourceURL)
            let internalPassword = try randomInternalPassword()
            try writePrivateFile(Data((internalPassword + "\n").utf8), at: passwordURL)
            try writePrivateFile(Data(), at: outputURL)

            let decoderOutput = Pipe()
            let decoderInput = Pipe()
            let decoder = Process()
            decoder.executableURL = openssl
            decoder.arguments = ["pkcs12", "-in", sourceURL.path, "-nodes", "-passin", "stdin"]
            decoder.standardInput = decoderInput
            decoder.standardOutput = decoderOutput
            decoder.standardError = FileHandle.nullDevice
            var decoderStarted = false
            defer {
                if decoderStarted && decoder.isRunning { decoder.terminate() }
                if decoderStarted { decoder.waitUntilExit() }
                try? decoderInput.fileHandleForWriting.close()
                try? decoderOutput.fileHandleForReading.close()
                try? decoderOutput.fileHandleForWriting.close()
            }
            let decryptedPEM: Data
            do {
                try decoder.run()
                decoderStarted = true
                try decoderOutput.fileHandleForWriting.close()
                try decoderInput.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
                try decoderInput.fileHandleForWriting.close()
                decryptedPEM = try decoderOutput.fileHandleForReading.readToEnd() ?? Data()
                decoder.waitUntilExit()
            } catch {
                throw AppleCertError.normalizationFailed("чтение исходного .p12")
            }
            guard decoder.terminationStatus == 0 else {
                throw AppleCertError.normalizationFailed("чтение исходного .p12, код \(decoder.terminationStatus)")
            }
            let components = try pemComponents(decryptedPEM)
            try writePrivateFile(components.certificates, at: certificatesURL)

            let keyInput = Pipe()
            let encoder = Process()
            // The system LibreSSL exporter produces the PKCS#12 envelope accepted by Security.framework.
            encoder.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            encoder.arguments = [
                "pkcs12", "-export", "-in", certificatesURL.path,
                "-inkey", "/dev/stdin", "-out", outputURL.path,
                "-descert", "-macalg", "sha1", "-passout", "file:\(passwordURL.path)"
            ]
            encoder.standardInput = keyInput
            encoder.standardOutput = FileHandle.nullDevice
            encoder.standardError = FileHandle.nullDevice
            var encoderStarted = false
            defer {
                if encoderStarted && encoder.isRunning { encoder.terminate() }
                if encoderStarted { encoder.waitUntilExit() }
                try? keyInput.fileHandleForWriting.close()
            }
            do {
                try encoder.run()
                encoderStarted = true
                // Only the public certificates are on disk; the private key stays in memory and this pipe.
                try keyInput.fileHandleForWriting.write(contentsOf: components.privateKey)
                try keyInput.fileHandleForWriting.close()
                encoder.waitUntilExit()
            } catch {
                throw AppleCertError.normalizationFailed("создание совместимого .p12")
            }
            guard encoder.terminationStatus == 0 else {
                throw AppleCertError.normalizationFailed("создание совместимого .p12, код \(encoder.terminationStatus)")
            }
            let data = try Data(contentsOf: outputURL)
            guard !data.isEmpty else { throw AppleCertError.normalizationFailed("пустой результат") }
            return (p12: data, password: internalPassword)
        }.value
    }

    private static func pemComponents(_ data: Data) throws -> (certificates: Data, privateKey: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppleCertError.normalizationFailed("кодировка PEM")
        }
        var certificates: [String] = []
        var privateKeys: [String] = []
        var label: String?
        var block: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("-----BEGIN "), line.hasSuffix("-----") {
                label = String(line.dropFirst("-----BEGIN ".count).dropLast("-----".count))
                block = [line]
            } else if let current = label {
                block.append(line)
                if line == "-----END \(current)-----" {
                    let pem = block.joined(separator: "\n") + "\n"
                    if current == "CERTIFICATE" { certificates.append(pem) }
                    if ["PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY"].contains(current) {
                        privateKeys.append(pem)
                    }
                    label = nil
                    block = []
                }
            }
        }
        guard !certificates.isEmpty, privateKeys.count == 1 else {
            throw AppleCertError.normalizationFailed("в PEM нужен один закрытый ключ и сертификат")
        }
        return (Data(certificates.joined().utf8), Data(privateKeys[0].utf8))
    }

    private static func openssl3URL() async throws -> URL {
        for path in ["/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"] {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let result = try? await ProcessRunner.checked(path, ["version"])
            if result?.output.hasPrefix("OpenSSL 3.") == true { return URL(fileURLWithPath: path) }
        }
        throw AppleCertError.normalizationToolUnavailable
    }

    private static func randomInternalPassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppleCertError.keychainFailure(errSecInternalComponent)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func writePrivateFile(_ data: Data, at url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw AppleCertError.normalizationFailed("временный файл")
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
    }

    private static func savePassword(_ password: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addition = query
            addition.merge(attributes) { _, new in new }
            let status = SecItemAdd(addition as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppleCertError.keychainFailure(status) }
        } else if updateStatus != errSecSuccess { throw AppleCertError.keychainFailure(updateStatus) }
    }

    private static func loadPassword() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else { throw AppleCertError.missingCredentials }
        return password
    }

    private static func loadProfile() async throws -> AppleCertProfile {
        try await decodeProfile(at: credentialURL("profile.mobileprovision"))
    }

    private static func credentialURL(_ name: String) throws -> URL {
        guard let id = UserDefaults.standard.string(forKey: activeIDKey), UUID(uuidString: id) != nil else { throw AppleCertError.missingCredentials }
        return try credentialsDirectory().appendingPathComponent(id).appendingPathComponent(name)
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = base.appendingPathComponent("WooFInstaller", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func credentialsDirectory() throws -> URL {
        let url = try applicationSupportDirectory().appendingPathComponent("AppleCert", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func signedIPADirectory() throws -> URL {
        let url = try applicationSupportDirectory().appendingPathComponent("SignedIPA", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
