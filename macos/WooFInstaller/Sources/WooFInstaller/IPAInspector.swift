import Foundation

struct PreparedIPA {
    let rootURL: URL
    let appURL: URL
    let inspection: IPAInspection

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

enum IPAInspectionError: LocalizedError {
    case invalidArchive
    case missingInfoPlist
    case invalidInfoPlist
    case missingProvisioningProfile
    case invalidProvisioningProfile

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "В IPA не найден пакет Payload/*.app."
        case .missingInfoPlist: return "В приложении отсутствует Info.plist."
        case .invalidInfoPlist: return "Не удалось прочитать параметры приложения из Info.plist."
        case .missingProvisioningProfile: return "В IPA отсутствует development/ad hoc provisioning profile."
        case .invalidProvisioningProfile: return "Не удалось проверить provisioning profile внутри IPA."
        }
    }
}

enum IPAInspector {
    static func prepare(_ ipaURL: URL) async throws -> PreparedIPA {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("woof-installer-ipa-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        do {
            _ = try await ProcessRunner.checked(
                "/usr/bin/ditto",
                ["-x", "-k", ipaURL.path, rootURL.path]
            )

            let payloadURL = rootURL.appendingPathComponent("Payload", isDirectory: true)
            let appURL = try fileManager.contentsOfDirectory(
                at: payloadURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first { $0.pathExtension == "app" }

            guard let appURL else { throw IPAInspectionError.invalidArchive }
            let infoURL = appURL.appendingPathComponent("Info.plist")
            guard fileManager.fileExists(atPath: infoURL.path) else {
                throw IPAInspectionError.missingInfoPlist
            }
            guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  let version = info["CFBundleShortVersionString"] as? String,
                  let build = info["CFBundleVersion"] as? String else {
                throw IPAInspectionError.invalidInfoPlist
            }

            _ = try await ProcessRunner.checked(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", appURL.path]
            )

            let profileURL = appURL.appendingPathComponent("embedded.mobileprovision")
            guard fileManager.fileExists(atPath: profileURL.path) else {
                throw IPAInspectionError.missingProvisioningProfile
            }
            let profileResult = try await ProcessRunner.checked(
                "/usr/bin/security",
                ["cms", "-D", "-i", profileURL.path]
            )
            guard let profile = try PropertyListSerialization.propertyList(
                from: profileResult.data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw IPAInspectionError.invalidProvisioningProfile
            }

            let inspection = IPAInspection(
                displayName: (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                version: version,
                build: build,
                teamName: profile["TeamName"] as? String,
                expirationDate: profile["ExpirationDate"] as? Date,
                provisionedDevices: Set(profile["ProvisionedDevices"] as? [String] ?? []),
                provisionsAllDevices: profile["ProvisionsAllDevices"] as? Bool ?? false
            )
            return PreparedIPA(rootURL: rootURL, appURL: appURL, inspection: inspection)
        } catch {
            try? fileManager.removeItem(at: rootURL)
            throw error
        }
    }
}
