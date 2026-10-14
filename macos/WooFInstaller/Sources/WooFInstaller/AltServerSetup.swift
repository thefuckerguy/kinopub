import AppKit
import Foundation

enum AltServerError: LocalizedError {
    case notInstalled
    case invalidSignature(String)
    case unsafeDownload
    case invalidArchive
    case applicationsNotWritable
    case runningDuringUpdate
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "AltServer не найден. Нажмите «Установить / обновить AltServer»."
        case let .invalidSignature(path):
            return "AltServer в \(path) не прошёл проверку официальной подписи или Gatekeeper. Установите официальный AltServer с altstore.io; существующее приложение не перезаписано."
        case .unsafeDownload:
            return "Не удалось получить официальный AltServer по HTTPS. Проверьте сеть или скачайте его с altstore.io."
        case .invalidArchive:
            return "Архив AltServer повреждён или содержит небезопасные пути. Установка отменена."
        case .applicationsNotWritable:
            return "Нет доступа для записи в /Applications. Скачайте официальный AltServer с altstore.io и перенесите его в «Программы» через Finder, подтвердив права администратора, затем нажмите «Открыть AltServer»."
        case .runningDuringUpdate:
            return "Для обновления завершите AltServer через его значок в строке меню и повторите установку."
        case let .restoreFailed(path):
            return "Не удалось завершить обновление. Предыдущий AltServer сохранён в \(path); восстановите его через Finder."
        }
    }
}

struct AltServerInstallation: Equatable {
    let appURL: URL
    let version: String
    let build: String

    func isOlder(than other: AltServerInstallation) -> Bool {
        AppVersion(version) < AppVersion(other.version)
            || (AppVersion(version) == AppVersion(other.version) && AppVersion(build) < AppVersion(other.build))
    }
}

enum AltServerPolicy {
    static let bundleID = "com.rileytestut.AltServer"
    static let teamID = "6XVY5G3U44"
    static let downloadURL = URL(string: "https://cdn.altstore.io/file/altstore/altserver.zip")!
    static let feedURL = URL(string: "https://altstore.io/altserver/sparkle-macos.xml")!
    static let guideURL = URL(string: "https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos")!
    static let signatureRequirement = "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        if url == feedURL || url == downloadURL { return true }
        return url.host == "cdn.altstore.io"
            && url.path.range(of: #"^/file/altstore/altserver/[0-9]+(?:_[0-9]+)*\.zip$"#, options: .regularExpression) != nil
    }
}

private final class OfficialAltServerRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(AltServerPolicy.allows) == true ? request : nil)
    }
}

/// Reads only the official feed's enclosure metadata; no external entities or HTML are loaded.
final class AltServerFeed: NSObject, XMLParserDelegate {
    private(set) var downloads: [(url: URL, version: String, build: String)] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard elementName == "enclosure", let rawURL = attributes["url"], let url = URL(string: rawURL),
              AltServerPolicy.allows(url), url != AltServerPolicy.feedURL,
              let version = attributes["sparkle:shortVersionString"],
              let build = attributes["sparkle:version"],
              version.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil,
              build.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else { return }
        downloads.append((url, version, build))
    }

    static func latestURL(in data: Data) throws -> URL {
        guard data.count <= 1_048_576 else { throw AltServerError.unsafeDownload }
        let delegate = AltServerFeed()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let latest = delegate.downloads.max(by: {
            let left = AltServerInstallation(appURL: $0.url, version: $0.version, build: $0.build)
            let right = AltServerInstallation(appURL: $1.url, version: $1.version, build: $1.build)
            return left.isOlder(than: right)
        }) else { throw AltServerError.unsafeDownload }
        return latest.url
    }
}

@MainActor
enum AltServerSetup {
    static func installed() async throws -> AltServerInstallation? {
        let manager = FileManager.default
        let candidates = [URL(fileURLWithPath: "/Applications/AltServer.app"),
                          manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/AltServer.app"),
                          NSWorkspace.shared.urlForApplication(withBundleIdentifier: AltServerPolicy.bundleID)]
            .compactMap { $0 }
        for url in candidates where manager.fileExists(atPath: url.path) {
            return try await validate(url)
        }
        return nil
    }

    static func validate(_ appURL: URL) async throws -> AltServerInstallation {
        do {
            let values = try appURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true,
                  let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == AltServerPolicy.bundleID,
                  let version = info["CFBundleShortVersionString"] as? String,
                  let build = info["CFBundleVersion"] as? String else { throw AltServerError.invalidSignature(appURL.path) }
            _ = try await ProcessRunner.checked("/usr/bin/codesign", [
                "--verify", "--deep", "--strict", "-R=\(AltServerPolicy.signatureRequirement)", appURL.path
            ])
            _ = try await ProcessRunner.checked("/usr/sbin/spctl", ["--assess", "--type", "execute", appURL.path])
            return AltServerInstallation(appURL: appURL, version: version, build: build)
        } catch {
            throw AltServerError.invalidSignature(appURL.path)
        }
    }

    /// Network and installation happen only after the user presses the setup button.
    static func prepare(progress: (String) -> Void) async throws -> AltServerInstallation {
        progress("Проверяю установленный AltServer…")
        let existing = try await installed()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: OfficialAltServerRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        progress("Проверяю официальный выпуск AltServer…")
        let (feed, feedResponse) = try await session.data(from: AltServerPolicy.feedURL)
        try validateResponse(feedResponse)
        let downloadURL = try AltServerFeed.latestURL(in: feed)
        progress("Скачиваю AltServer с cdn.altstore.io…")
        let (archiveURL, response) = try await session.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try validateResponse(response)
        let archive = try Data(contentsOf: archiveURL)
        try SafeAltServerArchive.validate(archive)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("woof-altserver-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: root) }
        progress("Проверяю архив, подпись AltServer и Gatekeeper…")
        // bsdtar also refuses archive entries that traverse a previously extracted symlink.
        _ = try await ProcessRunner.checked("/usr/bin/tar", ["-xf", archiveURL.path, "-C", root.path,
                                                                  "--no-same-owner", "--no-same-permissions"])
        let downloaded = try await validate(root.appendingPathComponent("AltServer.app"))
        if let existing, !existing.isOlder(than: downloaded) { return existing }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: AltServerPolicy.bundleID).isEmpty else {
            throw AltServerError.runningDuringUpdate
        }
        progress("Устанавливаю отдельно подписанный AltServer в /Applications…")
        return try await install(downloaded)
    }

    static func launch(_ installation: AltServerInstallation) async throws {
        // Revalidate immediately before launch, including apps that were already installed.
        _ = try await validate(installation.appURL)
        _ = try await ProcessRunner.checked("/usr/bin/open", ["-a", installation.appURL.path])
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = response.url, AltServerPolicy.allows(url) else { throw AltServerError.unsafeDownload }
    }

    private static func install(_ downloaded: AltServerInstallation) async throws -> AltServerInstallation {
        let manager = FileManager.default
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard manager.isWritableFile(atPath: applications.path) else { throw AltServerError.applicationsNotWritable }
        let destination = applications.appendingPathComponent("AltServer.app")
        // Do not move an installation from another folder or overwrite an unrelated app.
        if manager.fileExists(atPath: destination.path) {
            _ = try await validate(destination)
        }
        let stage = applications.appendingPathComponent(".woof-altserver-\(UUID().uuidString).app")
        defer { try? manager.removeItem(at: stage) }
        do {
            try manager.copyItem(at: downloaded.appURL, to: stage)
        } catch { throw AltServerError.applicationsNotWritable }
        _ = try await validate(stage)
        let backup = applications.appendingPathComponent(".AltServer-before-WooF-\(UUID().uuidString).app")
        let hasPrevious = manager.fileExists(atPath: destination.path)
        do {
            if hasPrevious { try manager.moveItem(at: destination, to: backup) }
            try manager.moveItem(at: stage, to: destination)
        } catch {
            if hasPrevious, manager.fileExists(atPath: backup.path) {
                do { try manager.moveItem(at: backup, to: destination) }
                catch { throw AltServerError.restoreFailed(backup.path) }
            }
            throw AltServerError.applicationsNotWritable
        }
        // The previous official app is retained as a recoverable hidden backup.
        return AltServerInstallation(appURL: destination, version: downloaded.version, build: downloaded.build)
    }
}
