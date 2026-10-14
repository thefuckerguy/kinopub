import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum SigningMode: String, CaseIterable, Identifiable {
    case appleCert
    case xcode

    var id: String { rawValue }
    var title: String { self == .appleCert ? "AppleCert" : "Xcode" }

    static func initialSelection(storedValue: String?, appleCertConfigured: Bool) -> SigningMode {
        if let storedValue, let storedMode = SigningMode(rawValue: storedValue) {
            return storedMode
        }
        return appleCertConfigured ? .appleCert : .xcode
    }
}

enum InstallerError: LocalizedError {
    case noDevice
    case noIPA
    case noRepository
    case appleCertRequired
    case invalidRepository
    case wrongBundleID(String)
    case expiredProfile
    case deviceNotProvisioned
    case dirtyRepository
    case noRelease
    case noIPAInRelease
    case insecureDownload
    case invalidDownloadDigest
    case malformedResponse
    case developerModeRequiresUSB
    case developerModePasscodeProtected
    case developerModeDisabled
    case developerCertificateNotTrusted
    case noWirelessDevices
    case wirelessDevicesNeedDeveloperMode([String])
    case wirelessBatchFailed(successful: [String], failures: [String])

    var errorDescription: String? {
        switch self {
        case .noDevice: return "Выберите подключённый iPhone или iPad."
        case .noIPA: return "Сначала выберите IPA‑файл."
        case .noRepository: return "Выберите папку репозитория kinopub."
        case .appleCertRequired: return "Для этой команды требуется настроенный AppleCert. Сохраните сертификат и provisioning profile."
        case .invalidRepository: return "В выбранной папке не найден ios/KinoPad.xcodeproj."
        case let .wrongBundleID(bundleID):
            return "Этот IPA имеет bundle ID \(bundleID), ожидался \(InstallerConstants.expectedBundleID)."
        case .expiredProfile: return "Срок действия provisioning profile в IPA истёк. Пересоберите приложение через Xcode."
        case .deviceNotProvisioned:
            return "Выбранное устройство отсутствует в профиле IPA. Используйте «Собрать и установить через Xcode» — телефон будет зарегистрирован безопасным способом."
        case .dirtyRepository:
            return "В репозитории есть незакоммиченные изменения. Сохраните их перед обновлением, чтобы установщик ничего не перезаписал."
        case .noRelease: return "В GitHub пока нет опубликованного релиза. Можно обновиться из ветки main и собрать приложение локально."
        case .noIPAInRelease: return "В последнем GitHub‑релизе нет IPA‑файла. Используйте локальную сборку через Xcode."
        case .insecureDownload: return "GitHub вернул небезопасный адрес загрузки. Загрузка отменена."
        case .invalidDownloadDigest: return "Контрольная сумма загруженного IPA не совпала с данными GitHub."
        case .malformedResponse: return "Получен неожиданный ответ от системной команды или GitHub."
        case .developerModeRequiresUSB:
            return "Для включения режима разработчика подключите и разблокируйте устройство кабелем USB. После перезагрузки подтвердите режим на самом устройстве."
        case .developerModePasscodeProtected:
            return "Apple не разрешает Mac автоматически включить Developer Mode на iPhone с код‑паролем. Не отключайте код‑пароль: на iPhone откройте «Настройки → Конфиденциальность и безопасность → Режим разработчика», включите переключатель, перезагрузитесь и подтвердите действие код‑паролем."
        case .developerModeDisabled:
            return "На выбранном устройстве выключен режим разработчика. Включите его в «Настройки → Конфиденциальность и безопасность → Режим разработчика», подтвердите перезагрузку и обновите список устройств."
        case .developerCertificateNotTrusted:
            return "WooF.Play установлена, но iPhone пока не доверяет сертификату разработчика. На iPhone откройте «Настройки → Основные → VPN и управление устройством», выберите профиль разработчика, нажмите «Доверять», затем откройте WooF.Play."
        case .noWirelessDevices:
            return "Нет iPhone или iPad, доступных по Wi‑Fi. Сначала один раз подключите и доверьте устройство Mac через Xcode, затем оставьте оба устройства в одной сети."
        case let .wirelessDevicesNeedDeveloperMode(names):
            return "На доступных по Wi‑Fi устройствах выключен режим разработчика: \(names.joined(separator: ", ")). Включите его на каждом устройстве и повторите обновление."
        case let .wirelessBatchFailed(successful, failures):
            let completed = successful.isEmpty
                ? ""
                : "Обновлено: \(successful.joined(separator: ", ")). "
            return "\(completed)Не удалось обновить: \(failures.joined(separator: "; "))."
        }
    }
}

@MainActor
final class InstallerModel: ObservableObject {
    @Published private(set) var devices: [IOSDevice] = []
    @Published var selectedDeviceID: String?
    @Published private(set) var installedVersion: String?
    @Published private(set) var installedBuild: String?
    @Published private(set) var ipaInspection: IPAInspection?
    @Published private(set) var githubRelease: GitHubRelease?
    @Published private(set) var gitBehindCount: Int?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage = "Подключите iPhone или iPad и нажмите «Обновить список»."
    @Published private(set) var isError = false
    @Published private(set) var lastLog = ""
    @Published private(set) var altServerDescription = "не проверено"
    @Published private(set) var altStoreDescription = "не проверено на устройстве"
    @Published var repositoryPath: String
    @Published var ipaPath: String
    @Published var signingMode: SigningMode {
        didSet { defaults.set(signingMode.rawValue, forKey: "signingMode") }
    }
    @Published private(set) var appleCertStatus: AppleCertStatus?
    @Published private(set) var appleCertConfigured = AppleCertSigning.isConfigured
    @Published var certificatePath = ""
    @Published var profilePath = ""

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferences = defaults
        let discoveredRepository = Self.discoverRepositoryPath()
        repositoryPath = preferences.string(forKey: "repositoryPath") ?? discoveredRepository
        ipaPath = preferences.string(forKey: "ipaPath") ?? ""
        signingMode = SigningMode.initialSelection(
            storedValue: preferences.string(forKey: "signingMode"),
            appleCertConfigured: AppleCertSigning.isConfigured
        )
        if preferences.string(forKey: "repositoryPath") == nil, !discoveredRepository.isEmpty {
            preferences.set(discoveredRepository, forKey: "repositoryPath")
        }
        if ipaPath.isEmpty, !repositoryPath.isEmpty {
            ipaPath = Self.discoverIPA(in: URL(fileURLWithPath: repositoryPath))?.path ?? ""
            if !ipaPath.isEmpty { preferences.set(ipaPath, forKey: "ipaPath") }
        }
    }

    var selectedDevice: IOSDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first { $0.id == selectedDeviceID }
    }

    var wirelessDevices: [IOSDevice] {
        devices.filter(\.isWireless)
    }

    var wirelessReadyDevices: [IOSDevice] {
        wirelessDevices.filter(\.developerModeEnabled)
    }

    var installedDescription: String {
        guard let installedVersion else { return "не установлено" }
        if let installedBuild { return "\(installedVersion) (\(installedBuild))" }
        return installedVersion
    }

    var canBuildWithSelectedSigningMode: Bool {
        signingMode == .xcode || appleCertConfigured
    }

    var signingModeHelp: String {
        switch signingMode {
        case .appleCert:
            return appleCertConfigured
                ? "Используется сохранённый AppleCert; выбранное устройство должно быть включено в provisioning profile."
                : "AppleCert выбран, но сохранённые данные отсутствуют. Добавьте сертификат и профиль или выберите Xcode. Сборка не переключится автоматически."
        case .xcode:
            return "Используется Xcode Automatic Signing. Сохранённые AppleCert данные игнорируются."
        }
    }

    var releaseDescription: String {
        guard let githubRelease else { return "не проверено" }
        let asset = githubRelease.ipaAsset == nil ? " · без IPA" : " · IPA доступен"
        return "\(githubRelease.tagName)\(asset)"
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку репозитория kinopub"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !repositoryPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: repositoryPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        repositoryPath = url.path
        defaults.set(url.path, forKey: "repositoryPath")
        if let discoveredIPA = Self.discoverIPA(in: url) {
            ipaPath = discoveredIPA.path
            defaults.set(discoveredIPA.path, forKey: "ipaPath")
        }
        statusMessage = "Репозиторий выбран."
        isError = false
    }

    func chooseIPA() {
        let panel = NSOpenPanel()
        panel.title = "Выберите подписанный IPA"
        panel.allowedContentTypes = [.init(filenameExtension: "ipa")!]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !ipaPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: ipaPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ipaPath = url.path
        defaults.set(url.path, forKey: "ipaPath")
        inspectSelectedIPA()
    }

    func chooseAppleCertificate() {
        let panel = NSOpenPanel()
        panel.title = "Выберите сертификат AppleCert (.p12)"
        panel.allowedContentTypes = [.init(filenameExtension: "p12")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        certificatePath = url.path
    }

    func chooseAppleProfile() {
        let panel = NSOpenPanel()
        panel.title = "Выберите matching provisioning profile (.mobileprovision)"
        panel.allowedContentTypes = [.init(filenameExtension: "mobileprovision")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        profilePath = url.path
    }

    func refreshAppleCertStatus() {
        Task {
            do {
                appleCertStatus = try await AppleCertSigning.status()
                appleCertConfigured = appleCertStatus != nil
            } catch {
                appleCertConfigured = false
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }

    func configureAppleCert(password: String) {
        runOperation("Проверяю AppleCert сертификат и профиль…") { [weak self] in
            guard let self else { return "" }
            guard !self.certificatePath.isEmpty, !self.profilePath.isEmpty else {
                throw AppleCertError.missingCredentials
            }
            let status = try await AppleCertSigning.configure(
                p12URL: URL(fileURLWithPath: self.certificatePath),
                password: password,
                profileURL: URL(fileURLWithPath: self.profilePath)
            )
            self.appleCertStatus = status
            self.appleCertConfigured = true
            self.signingMode = .appleCert
            self.certificatePath = ""
            self.profilePath = ""
            return "AppleCert настроен: \(status.profileName). AppleCert выбран для следующих сборок."
        }
    }

    func removeAppleCert() {
        runOperation("Удаляю сохранённые AppleCert данные…") { [weak self] in
            guard let self else { return "" }
            try AppleCertSigning.remove()
            self.appleCertStatus = nil
            self.appleCertConfigured = false
            self.signingMode = .xcode
            return "AppleCert данные удалены. Следующие сборки будут подписываться через Xcode."
        }
    }

    func openRepositoryOnGitHub() {
        NSWorkspace.shared.open(InstallerConstants.githubURL)
    }

    func openAppStoreConnect() {
        NSWorkspace.shared.open(InstallerConstants.appStoreConnectURL)
    }

    func openDeveloperEnrollment() {
        NSWorkspace.shared.open(InstallerConstants.developerEnrollmentURL)
    }

    func prepareAltServer() {
        runOperation("Готовлю AltServer для обновления подписи…") { [weak self] in
            guard let self else { return "" }
            self.altServerDescription = "проверка…"
            do {
                let installation = try await AltServerSetup.prepare { self.statusMessage = $0 }
                self.altServerDescription = "\(installation.version) (\(installation.build)) · подпись проверена"
                try await AltServerSetup.launch(installation)
                return "AltServer запущен в строке меню. Установите AltStore через его меню и введите Apple Account / код 2FA только в AltServer. Затем установите IPA WooF.Play через AltStore на iPhone/iPad — только после этого AltStore сможет обновлять подпись в фоне."
            } catch {
                self.altServerDescription = "настройка не завершена"
                throw error
            }
        }
    }

    func launchAltServer() {
        runOperation("Проверяю подпись и открываю AltServer…") { [weak self] in
            guard let self else { return "" }
            guard let installation = try await AltServerSetup.installed() else {
                self.altServerDescription = "не установлен"
                throw AltServerError.notInstalled
            }
            try await AltServerSetup.launch(installation)
            self.altServerDescription = "\(installation.version) (\(installation.build)) · подпись проверена"
            return "AltServer открыт в строке меню. Для фонового обновления установите WooF.Play через AltStore и оставьте Mac с запущенным AltServer в одной сети с устройством."
        }
    }

    func openAltStoreGuide() {
        NSWorkspace.shared.open(AltServerPolicy.guideURL)
    }

    func revealIPAForAltStore() {
        guard !ipaPath.isEmpty, FileManager.default.fileExists(atPath: ipaPath) else {
            statusMessage = InstallerError.noIPA.localizedDescription
            isError = true
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: ipaPath)])
    }

    func sendIPAtoAltStore() {
        runOperation("Проверяю AltStore Classic и готовлю IPA…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            guard device.developerModeEnabled else { throw InstallerError.developerModeDisabled }
            self.altStoreDescription = "не проверено на устройстве"
            let installation = try await AltStoreTransfer.discover(on: device)
            self.altStoreDescription = "\(installation.version ?? "Classic") · \(device.name)"
            let source = try self.selectedIPAURL()
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AltStoreIPASnapshot.create(from: source)
            }.value
            defer { snapshot.remove() }
            let prepared = try await IPAInspector.prepare(snapshot.url)
            defer { prepared.removeTemporaryFiles() }
            // AltStore resigns the IPA: the old profile's expiry and UDIDs do not apply.
            try self.validateBundle(prepared.inspection)
            self.ipaInspection = prepared.inspection
            self.statusMessage = "Передаю IPA в AltStore на \(device.name)…"
            try await AltStoreTransfer.send(snapshot: snapshot, to: device, installation: installation)
            return "IPA передан, AltStore открыт на \(device.name). Подтвердите импорт и установку на устройстве; если потребуется, войдите в Apple Account внутри AltStore. Это ещё не подтверждение установки WooF.Play."
        }
    }

    func refreshDevices() {
        runOperation("Ищу подключённые устройства…") { [weak self] in
            guard let self else { return "" }
            return try await self.refreshDevicesInternal()
        }
    }

    func selectedDeviceChanged() {
        altStoreDescription = "не проверено на устройстве"
        guard selectedDevice != nil else {
            installedVersion = nil
            installedBuild = nil
            return
        }
        runOperation("Проверяю установленную версию…") { [weak self] in
            guard let self else { return "" }
            try await self.refreshInstalledVersionInternal()
            return "Данные устройства обновлены."
        }
    }

    func inspectSelectedIPA() {
        runOperation("Проверяю IPA и подпись…") { [weak self] in
            guard let self else { return "" }
            let url = try self.selectedIPAURL()
            let prepared = try await IPAInspector.prepare(url)
            defer { prepared.removeTemporaryFiles() }
            try self.validateBundle(prepared.inspection)
            self.ipaInspection = prepared.inspection
            return "IPA проверен: \(prepared.inspection.displayName) \(prepared.inspection.version) (\(prepared.inspection.build))."
        }
    }

    func installSelectedIPA() {
        runOperation("Проверяю и устанавливаю IPA…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            let prepared = try await IPAInspector.prepare(self.selectedIPAURL())
            defer { prepared.removeTemporaryFiles() }
            try self.validate(prepared.inspection, for: device)
            self.ipaInspection = prepared.inspection
            try await self.install(appURL: prepared.appURL, on: device)
            try await self.refreshInstalledVersionInternal()
            return "WooF.Play \(prepared.inspection.version) установлен на \(device.name)."
        }
    }

    func buildLocalChangesAndInstall() {
        runOperation("Собираю текущие локальные исходники с \(signingMode.title)…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            try await self.buildAndInstallInternal(on: device)
            return "Текущая локальная сборка WooF.Play установлена на \(device.name). Git-репозиторий не изменялся."
        }
    }

    func automaticallyInstallOrUpdate() {
        runOperation("Проверяю обновления и готовлю WooF.Play…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            guard device.developerModeEnabled else {
                throw InstallerError.developerModeDisabled
            }

            let repository = try self.requireRepository()
            try await self.ensureTrackedFilesAreClean(repository)
            let wasInstalled = self.installedVersion != nil
            let behindCount = try await self.checkGitUpdatesInternal()
            if behindCount > 0 {
                let pull = try await self.runGit(
                    ["pull", "--ff-only", "origin", "main"],
                    repository: repository
                )
                self.record(pull.output)
                self.gitBehindCount = 0
            }

            try await self.buildAndInstallInternal(on: device)
            let action = wasInstalled ? "обновлена" : "установлена"
            let source = behindCount > 0
                ? "Исходники обновлены из GitHub."
                : "Использована актуальная локальная версия."
            return "WooF.Play \(action) и запущена на \(device.name). \(source)"
        }
    }

    func updateAllAvailableDevicesOverWiFi() {
        runOperation("Ищу устройства и готовлю обновление по Wi‑Fi…") { [weak self] in
            guard let self else { return "" }
            try await self.discoverDevicesInternal()

            let wirelessDevices = self.wirelessDevices
            guard !wirelessDevices.isEmpty else {
                throw InstallerError.noWirelessDevices
            }
            let targets = self.wirelessReadyDevices
            guard !targets.isEmpty else {
                throw InstallerError.wirelessDevicesNeedDeveloperMode(
                    wirelessDevices.map(\.name)
                )
            }

            let repository = try self.requireRepository()
            try await self.ensureTrackedFilesAreClean(repository)
            let behindCount = try await self.checkGitUpdatesInternal()
            if behindCount > 0 {
                let pull = try await self.runGit(
                    ["pull", "--ff-only", "origin", "main"],
                    repository: repository
                )
                self.record(pull.output)
                self.gitBehindCount = 0
            }

            var successful: [String] = []
            var failures = wirelessDevices
                .filter { !$0.developerModeEnabled }
                .map { "\($0.name): режим разработчика выключен" }
            for (index, device) in targets.enumerated() {
                self.statusMessage = "Обновляю \(device.name) по Wi‑Fi — \(index + 1) из \(targets.count)…"
                do {
                    try await self.buildAndInstallInternal(
                        on: device,
                        launchAfterInstall: false
                    )
                    successful.append(device.name)
                } catch {
                    let failure = "\(device.name): \(error.localizedDescription)"
                    failures.append(failure)
                    self.record(failure)
                }
            }

            if !failures.isEmpty {
                throw InstallerError.wirelessBatchFailed(
                    successful: successful,
                    failures: failures
                )
            }
            let source = behindCount > 0
                ? "Исходники получены из GitHub."
                : "Использована актуальная локальная версия."
            return "WooF.Play обновлена по Wi‑Fi на всех доступных устройствах: \(successful.joined(separator: ", ")). \(source)"
        }
    }

    func enableDeveloperMode() {
        runOperation("Отправляю устройству запрос на включение режима разработчика…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            let result = try await ProcessRunner.run(
                "/usr/bin/devmodectl",
                ["single", device.id]
            )
            self.record(result.output)
            guard result.status == 0 else {
                if result.output.localizedCaseInsensitiveContains("not connected") {
                    throw InstallerError.developerModeRequiresUSB
                }
                if result.output.localizedCaseInsensitiveContains("passcode set") {
                    throw InstallerError.developerModePasscodeProtected
                }
                throw CommandFailure.failed(
                    executable: "devmodectl",
                    status: result.status,
                    output: result.output
                )
            }
            return "Запрос отправлен. Завершите перезагрузку и подтвердите режим разработчика на iPhone/iPad, затем обновите список устройств."
        }
    }

    func checkGitUpdates() {
        runOperation("Проверяю обновления ветки main…") { [weak self] in
            guard let self else { return "" }
            let count = try await self.checkGitUpdatesInternal()
            return count == 0
                ? "Локальные исходники уже соответствуют origin/main."
                : "В origin/main доступно обновлений: \(count)."
        }
    }

    func updateFromGitAndInstall() {
        runOperation("Обновляю исходники и собираю приложение…") { [weak self] in
            guard let self else { return "" }
            let device = try self.requireDevice()
            let repository = try self.requireRepository()
            try await self.ensureTrackedFilesAreClean(repository)
            let pull = try await self.runGit(
                ["pull", "--ff-only", "origin", "main"],
                repository: repository
            )
            self.record(pull.output)
            self.gitBehindCount = 0
            try await self.buildAndInstallInternal(on: device)
            return "Исходники обновлены из GitHub, новая сборка установлена на \(device.name)."
        }
    }

    func checkGitHubRelease() {
        runOperation("Проверяю последний релиз GitHub…") { [weak self] in
            guard let self else { return "" }
            let release = try await self.fetchLatestRelease()
            self.githubRelease = release
            guard let asset = release.ipaAsset else { throw InstallerError.noIPAInRelease }
            let comparison: String
            if let installedVersion = self.installedVersion,
               AppVersion(installedVersion) >= AppVersion(release.tagName) {
                comparison = "Установленная версия не старее релиза."
            } else {
                comparison = "Доступно обновление."
            }
            return "GitHub: \(release.tagName), \(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)). \(comparison)"
        }
    }

    func downloadReleaseIPA() {
        runOperation("Скачиваю и проверяю IPA из GitHub…") { [weak self] in
            guard let self else { return "" }
            let release: GitHubRelease
            if let existingRelease = self.githubRelease {
                release = existingRelease
            } else {
                release = try await self.fetchLatestRelease()
            }
            guard let asset = release.ipaAsset else { throw InstallerError.noIPAInRelease }
            let downloadedURL = try await self.download(asset: asset, release: release)
            let prepared = try await IPAInspector.prepare(downloadedURL)
            defer { prepared.removeTemporaryFiles() }
            try self.validateBundle(prepared.inspection)
            self.ipaInspection = prepared.inspection
            self.ipaPath = downloadedURL.path
            self.defaults.set(downloadedURL.path, forKey: "ipaPath")
            return "IPA \(prepared.inspection.version) скачан и проверен. Теперь его можно установить."
        }
    }

    private func runOperation(
        _ message: String,
        operation: @escaping @MainActor () async throws -> String
    ) {
        guard !isBusy else { return }
        isBusy = true
        isError = false
        statusMessage = message
        lastLog = ""
        Task {
            do {
                statusMessage = try await operation()
                isError = false
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isBusy = false
        }
    }

    private func refreshDevicesInternal() async throws -> String {
        try await discoverDevicesInternal()
        if selectedDevice != nil {
            try await refreshInstalledVersionInternal()
        } else {
            installedVersion = nil
            installedBuild = nil
        }
        return devices.isEmpty
            ? "Устройства не найдены. Разблокируйте телефон, подтвердите доверие и включите режим разработчика."
            : "Найдено устройств: \(devices.count)."
    }

    private func discoverDevicesInternal() async throws {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-installer-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        let command = try await ProcessRunner.checked(
            "/usr/bin/xcrun",
            ["devicectl", "list", "devices", "--json-output", jsonURL.path]
        )
        record(command.output)
        let document = try JSONDecoder().decode(
            DeviceListDocument.self,
            from: Data(contentsOf: jsonURL)
        )
        devices = document.result.devices.compactMap(\.installerDevice).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first?.id
        }
    }

    private func refreshInstalledVersionInternal() async throws {
        guard let device = selectedDevice else { throw InstallerError.noDevice }
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-installer-apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        let command = try await ProcessRunner.checked(
            "/usr/bin/xcrun",
            [
                "devicectl", "device", "info", "apps",
                "--device", device.id,
                "--bundle-id", InstallerConstants.expectedBundleID,
                "--json-output", jsonURL.path
            ]
        )
        record(command.output)
        let document = try JSONDecoder().decode(
            InstalledAppsDocument.self,
            from: Data(contentsOf: jsonURL)
        )
        let app = document.result.apps.first {
            $0.bundleIdentifier == InstallerConstants.expectedBundleID
        }
        installedVersion = app?.version
        installedBuild = app?.bundleVersion
    }

    private func buildAndInstallInternal(
        on device: IOSDevice,
        launchAfterInstall: Bool = true
    ) async throws {
        switch signingMode {
        case .appleCert:
            guard AppleCertSigning.isConfigured else { throw InstallerError.appleCertRequired }
            try await buildSignAndInstallWithAppleCert(on: device, launchAfterInstall: launchAfterInstall)
        case .xcode:
            try await buildAndInstallWithXcode(on: device, launchAfterInstall: launchAfterInstall)
        }
    }

    private func buildAndInstallWithXcode(
        on device: IOSDevice,
        launchAfterInstall: Bool
    ) async throws {
        let repository = try requireRepository()
        let projectURL = repository.appendingPathComponent("ios/KinoPad.xcodeproj")
        let derivedDataURL = try applicationSupportDirectory()
            .appendingPathComponent("DerivedData/\(device.id)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: derivedDataURL,
            withIntermediateDirectories: true
        )
        let build = try await ProcessRunner.checked(
            "/usr/bin/xcodebuild",
            [
                "build",
                "-project", projectURL.path,
                "-scheme", "KinoPad",
                "-configuration", "Release",
                "-destination", "platform=iOS,id=\(device.id)",
                "-derivedDataPath", derivedDataURL.path,
                "-allowProvisioningUpdates",
                "-allowProvisioningDeviceRegistration",
                "CODE_SIGN_STYLE=Automatic"
            ],
            currentDirectory: repository
        )
        record(build.output)
        let appURL = derivedDataURL
            .appendingPathComponent("Build/Products/Release-iphoneos/KinoPad.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw InstallerError.malformedResponse
        }
        let signature = try await ProcessRunner.checked(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path]
        )
        record(signature.output)
        try await install(
            appURL: appURL,
            on: device,
            launchAfterInstall: launchAfterInstall
        )
        if selectedDeviceID == device.id {
            try await refreshInstalledVersionInternal()
        }
    }

    private func buildSignAndInstallWithAppleCert(
        on device: IOSDevice,
        launchAfterInstall: Bool
    ) async throws {
        try await AppleCertSigning.validateSaved(for: device.id)
        let repository = try requireRepository()
        let projectURL = repository.appendingPathComponent("ios/KinoPad.xcodeproj")
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("woof-applecert-build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let derivedDataURL = temporaryRoot.appendingPathComponent("DerivedData", isDirectory: true)
        let build = try await ProcessRunner.checked(
            "/usr/bin/xcodebuild",
            [
                "build",
                "-project", projectURL.path,
                "-scheme", "KinoPad",
                "-configuration", "Release",
                "-destination", "generic/platform=iOS",
                "-derivedDataPath", derivedDataURL.path,
                "CODE_SIGNING_ALLOWED=NO"
            ],
            currentDirectory: repository
        )
        record(build.output)
        let appURL = derivedDataURL.appendingPathComponent("Build/Products/Release-iphoneos/KinoPad.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else { throw AppleCertError.invalidApp }
        let signedIPA = try await AppleCertSigning.signAndPackage(appURL: appURL, deviceID: device.id)
        ipaPath = signedIPA.path
        defaults.set(signedIPA.path, forKey: "ipaPath")
        try await install(appURL: appURL, on: device, launchAfterInstall: launchAfterInstall)
        if selectedDeviceID == device.id { try await refreshInstalledVersionInternal() }
    }

    private func install(
        appURL: URL,
        on device: IOSDevice,
        launchAfterInstall: Bool = true
    ) async throws {
        let installation = try await ProcessRunner.checked(
            "/usr/bin/xcrun",
            ["devicectl", "device", "install", "app", "--device", device.id, appURL.path]
        )
        record(installation.output)
        guard launchAfterInstall else { return }
        let launch = try await ProcessRunner.run(
            "/usr/bin/xcrun",
            [
                "devicectl", "device", "process", "launch",
                "--device", device.id,
                "--terminate-existing",
                InstallerConstants.expectedBundleID
            ]
        )
        record(launch.output)
        guard launch.status == 0 else {
            if launch.output.localizedCaseInsensitiveContains("not been explicitly trusted") {
                throw InstallerError.developerCertificateNotTrusted
            }
            throw CommandFailure.failed(
                executable: "xcrun devicectl device process launch",
                status: launch.status,
                output: launch.output
            )
        }
    }

    private func checkGitUpdatesInternal() async throws -> Int {
        let repository = try requireRepository()
        let fetch = try await runGit(["fetch", "origin", "main", "--prune"], repository: repository)
        record(fetch.output)
        let countResult = try await runGit(
            ["rev-list", "--count", "HEAD..origin/main"],
            repository: repository
        )
        record(countResult.output)
        guard let count = Int(countResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw InstallerError.malformedResponse
        }
        gitBehindCount = count
        return count
    }

    private func ensureTrackedFilesAreClean(_ repository: URL) async throws {
        let result = try await runGit(
            ["status", "--porcelain", "--untracked-files=no"],
            repository: repository
        )
        guard result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InstallerError.dirtyRepository
        }
    }

    private func runGit(_ arguments: [String], repository: URL) async throws -> CommandResult {
        try await ProcessRunner.checked(
            "/usr/bin/git",
            ["-C", repository.path] + arguments,
            currentDirectory: repository
        )
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(InstallerConstants.githubRepository)/releases/latest") else {
            throw InstallerError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.setValue("WooF-Installer/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstallerError.malformedResponse
        }
        if httpResponse.statusCode == 404 { throw InstallerError.noRelease }
        guard httpResponse.statusCode == 200 else { throw InstallerError.malformedResponse }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft else { throw InstallerError.noRelease }
        return release
    }

    private func download(asset: GitHubReleaseAsset, release: GitHubRelease) async throws -> URL {
        guard asset.browserDownloadURL.scheme == "https",
              asset.browserDownloadURL.host == "github.com" else {
            throw InstallerError.insecureDownload
        }
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("WooF-Installer/0.1", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw InstallerError.malformedResponse
        }

        let downloadsURL = try applicationSupportDirectory()
            .appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: asset.name).lastPathComponent
        let destination = downloadsURL.appendingPathComponent(
            "\(release.tagName)-\(UUID().uuidString.prefix(8))-\(safeName)"
        )
        try FileManager.default.copyItem(at: temporaryURL, to: destination)

        if let digest = asset.digest,
           digest.lowercased().hasPrefix("sha256:") {
            let expected = String(digest.dropFirst("sha256:".count)).lowercased()
            let actual = SHA256.hash(data: try Data(contentsOf: destination))
                .map { String(format: "%02x", $0) }
                .joined()
            guard actual == expected else {
                try? FileManager.default.removeItem(at: destination)
                throw InstallerError.invalidDownloadDigest
            }
        }
        return destination
    }

    private func validateBundle(_ inspection: IPAInspection) throws {
        guard inspection.bundleID == InstallerConstants.expectedBundleID else {
            throw InstallerError.wrongBundleID(inspection.bundleID)
        }
        if let expirationDate = inspection.expirationDate, expirationDate <= Date() {
            throw InstallerError.expiredProfile
        }
    }

    private func validate(_ inspection: IPAInspection, for device: IOSDevice) throws {
        try validateBundle(inspection)
        guard inspection.supports(deviceID: device.id) else {
            throw InstallerError.deviceNotProvisioned
        }
    }

    private func requireDevice() throws -> IOSDevice {
        guard let selectedDevice else { throw InstallerError.noDevice }
        return selectedDevice
    }

    private func selectedIPAURL() throws -> URL {
        guard !ipaPath.isEmpty,
              FileManager.default.fileExists(atPath: ipaPath) else {
            throw InstallerError.noIPA
        }
        return URL(fileURLWithPath: ipaPath)
    }

    private func requireRepository() throws -> URL {
        guard !repositoryPath.isEmpty else { throw InstallerError.noRepository }
        let url = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        guard FileManager.default.fileExists(
            atPath: url.appendingPathComponent("ios/KinoPad.xcodeproj").path
        ) else {
            throw InstallerError.invalidRepository
        }
        return url
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = baseURL.appendingPathComponent("WooFInstaller", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let combined = lastLog.isEmpty ? trimmed : "\(lastLog)\n\n\(trimmed)"
        lastLog = String(combined.suffix(24_000))
    }

    private static func discoverRepositoryPath() -> String {
        var candidates = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)]
        var ancestor = Bundle.main.bundleURL
        for _ in 0..<8 {
            ancestor.deleteLastPathComponent()
            candidates.append(ancestor)
        }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("ios/KinoPad.xcodeproj").path)
        }?.path ?? ""
    }

    private static func discoverIPA(in repository: URL) -> URL? {
        let directory = repository.appendingPathComponent("ios/build/installer", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .first
    }
}
