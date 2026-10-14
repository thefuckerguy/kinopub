import Darwin
import Foundation

enum AltStoreTransferError: LocalizedError {
    case notInstalled, ambiguousInstallation, containerUnavailable, invalidIPA, launchFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "На выбранном устройстве не найден AltStore Classic. Установите его через меню AltServer → Install AltStore; AltStore PAL для этого сценария не подходит."
        case .ambiguousInstallation:
            return "На устройстве найдено несколько копий AltStore Classic. Оставьте одну нужную копию и повторите передачу."
        case .containerUnavailable:
            return "iOS не предоставила доступ к контейнеру AltStore Classic. Разблокируйте устройство, проверьте доверие к Mac и режим разработчика. IPA можно также передать через AirDrop и импортировать кнопкой «+» в My Apps."
        case .invalidIPA:
            return "Для передачи нужен обычный IPA‑файл размером от 1 байта до 512 МиБ; ссылки и специальные файлы не поддерживаются."
        case .launchFailed:
            return "IPA скопирован в AltStore, но открыть импорт на устройстве не удалось. Разблокируйте устройство, проверьте доверие к сертификату AltStore и повторите передачу."
        }
    }
}

struct AltStoreInstallation: Equatable {
    let bundleID: String
    let version: String?
    let containerURL: URL

    // A dedicated file in the app's temporary directory bounds retained data to one IPA.
    // iOS can purge it; AltStore copies imported IPAs into its own installation workspace.
    static let destination = "tmp/WooFInstaller/WooF.Play.ipa"

    static func isClassicBundleID(_ identifier: String) -> Bool {
        func isTeamID(_ value: Substring) -> Bool {
            value.count == 10 && value.utf8.allSatisfy {
                (65...90).contains($0) || (48...57).contains($0)
            }
        }
        return ["com.rileytestut.AltStore", "com.rileytestut.AltStore.Beta"].contains { base in
            if identifier == base { return true }
            // Current AltServer: com.<TEAM>.com.rileytestut.AltStore.
            let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count >= 3, parts[0] == "com", isTeamID(parts[1]),
               parts.dropFirst(2).joined(separator: ".") == base { return true }
            // Older signing tools may append the team to the original identifier.
            guard identifier.hasPrefix(base + ".") else { return false }
            return isTeamID(identifier.dropFirst(base.count + 1))
        }
    }

    static func detect(in apps: [InstalledApp]) throws -> Self {
        let matches = apps.filter { isClassicBundleID($0.bundleIdentifier) }
        guard !matches.isEmpty else { throw AltStoreTransferError.notInstalled }
        guard matches.count == 1, let app = matches.first else {
            throw AltStoreTransferError.ambiguousInstallation
        }
        guard app.containerAccessible == true, let path = app.dataContainerPath else {
            throw AltStoreTransferError.containerUnavailable
        }
        let roots = ["/private/var/mobile/Containers/Data/Application/", "/var/mobile/Containers/Data/Application/"]
        guard let root = roots.first(where: { path.hasPrefix($0) }),
              UUID(uuidString: String(path.dropFirst(root.count))) != nil else {
            throw AltStoreTransferError.containerUnavailable
        }
        return Self(bundleID: app.bundleIdentifier, version: app.version,
                    containerURL: URL(fileURLWithPath: path, isDirectory: true))
    }

    var importURL: URL { containerURL.appendingPathComponent(Self.destination) }

    var handoffURL: URL {
        var components = URLComponents()
        components.scheme = usesClassicScheme ? "altstore-classic" : "altstore"
        components.host = "install"
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encodedFileURL = importURL.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved)!
        components.percentEncodedQueryItems = [URLQueryItem(name: "url", value: encodedFileURL)]
        return components.url!
    }

    private var usesClassicScheme: Bool {
        guard let version else { return true }
        let numbers = version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let major = numbers.first else { return true }
        if major != 2 { return major > 2 }
        return (numbers.dropFirst().first ?? 0) >= 2
    }

    func copyArguments(deviceID: String, source: URL) -> [String] {
        ["devicectl", "device", "copy", "to", "--device", deviceID,
         "--source", source.path, "--domain-type", "appDataContainer",
         "--domain-identifier", bundleID, "--destination", Self.destination,
         "--timeout", "120"]
    }

    func launchArguments(deviceID: String) -> [String] {
        ["devicectl", "device", "process", "launch", "--device", deviceID,
         "--terminate-existing", "--payload-url", handoffURL.absoluteString,
         "--timeout", "30", bundleID]
    }
}

struct AltStoreIPASnapshot {
    static let maximumFileBytes: Int64 = 512 * 1_024 * 1_024
    let url: URL
    var directory: URL { url.deletingLastPathComponent() }

    static func create(from source: URL) throws -> Self {
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw AltStoreTransferError.invalidIPA }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard source.pathExtension.lowercased() == "ipa",
              fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumFileBytes else {
            throw AltStoreTransferError.invalidIPA
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-altstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            let snapshot = directory.appendingPathComponent("WooF.Play.ipa")
            let outputDescriptor = open(snapshot.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard outputDescriptor >= 0 else { throw AltStoreTransferError.invalidIPA }
            let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
            defer { try? output.close() }
            var copied: Int64 = 0
            while let block = try input.read(upToCount: 65_536), !block.isEmpty {
                copied += Int64(block.count)
                guard copied <= info.st_size else { throw AltStoreTransferError.invalidIPA }
                try output.write(contentsOf: block)
            }
            var after = stat()
            guard fstat(descriptor, &after) == 0, copied == info.st_size,
                  after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec else {
                throw AltStoreTransferError.invalidIPA
            }
            return Self(url: snapshot)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

enum AltStoreTransfer {
    static func discover(on device: IOSDevice) async throws -> AltStoreInstallation {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-altstore-apps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let jsonURL = directory.appendingPathComponent("apps.json")
        _ = try await ProcessRunner.checked("/usr/bin/xcrun", [
            "devicectl", "device", "info", "apps", "--device", device.id,
            "--include-container-paths", "--timeout", "30", "--json-output", jsonURL.path
        ])
        let document = try JSONDecoder().decode(InstalledAppsDocument.self, from: Data(contentsOf: jsonURL))
        return try AltStoreInstallation.detect(in: document.result.apps)
    }

    static func send(snapshot: AltStoreIPASnapshot, to device: IOSDevice,
                     installation: AltStoreInstallation,
                     run: (String, [String]) async throws -> CommandResult = { executable, arguments in
                         try await ProcessRunner.run(executable, arguments)
                     }) async throws {
        let copy = try await run("/usr/bin/xcrun",
            installation.copyArguments(deviceID: device.id, source: snapshot.url))
        guard copy.status == 0 else {
            throw CommandFailure.failed(executable: "xcrun devicectl device copy to",
                                        status: copy.status, output: copy.output)
        }
        let result = try await run("/usr/bin/xcrun",
            installation.launchArguments(deviceID: device.id))
        guard result.status == 0 else { throw AltStoreTransferError.launchFailed }
    }
}
