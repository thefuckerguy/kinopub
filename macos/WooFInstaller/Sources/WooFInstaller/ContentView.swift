import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InstallerModel
    @State private var showsDeveloperModeConfirmation = false
    @State private var certificatePassword = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selectedDeviceID) {
                    Section("iPhone и iPad") {
                        ForEach(model.devices) { device in
                            DeviceRow(device: device)
                                .tag(device.id)
                        }
                    }
                }
                .overlay {
                    if model.devices.isEmpty && !model.isBusy {
                        ContentUnavailableView(
                            "Устройства не найдены",
                            systemImage: "iphone.slash",
                            description: Text("Подключите и разблокируйте устройство.")
                        )
                    }
                }

                Divider()
                Button {
                    model.refreshDevices()
                } label: {
                    Label("Обновить список", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statusCard
                    installationCard
                    appleCertCard
                    altServerCard
                    updatesCard
                    if !model.lastLog.isEmpty { logCard }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: model.selectedDeviceID) { _, _ in
            model.selectedDeviceChanged()
        }
        .task {
            if model.devices.isEmpty { model.refreshDevices() }
            model.refreshAppleCertStatus()
        }
        .confirmationDialog(
            "Включить режим разработчика?",
            isPresented: $showsDeveloperModeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Включить и перезагрузить устройство") {
                model.enableDeveloperMode()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Подключите устройство кабелем. Если на iPhone установлен код‑пароль, Apple потребует включить переключатель вручную в «Настройки → Конфиденциальность и безопасность → Режим разработчика». Затем подтвердите перезагрузку и повторное включение код‑паролем.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("WooF Installer").font(.largeTitle.bold())
                Text("Безопасная установка и обновление WooF.Play")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("GitHub", systemImage: "safari") {
                model.openRepositoryOnGitHub()
            }
        }
    }

    private var statusCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(model.isError ? .orange : .green)
                }
                Text(model.statusMessage)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(4)
        }
    }

    private var installationCard: some View {
        GroupBox("Установка") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Способ подписи", selection: $model.signingMode) {
                    ForEach(SigningMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)
                Text(model.signingModeHelp)
                    .font(.caption)
                    .foregroundStyle(model.signingMode == .appleCert && !model.appleCertConfigured ? Color.orange : Color.secondary)
                LabeledContent("Устройство") {
                    Text(model.selectedDevice?.name ?? "не выбрано")
                }
                LabeledContent("Установлено") {
                    Text(model.installedDescription)
                }
                Button {
                    model.automaticallyInstallOrUpdate()
                } label: {
                    Label("Установить / обновить на выбранном устройстве", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.selectedDevice == nil || model.repositoryPath.isEmpty || !model.canBuildWithSelectedSigningMode)
                Text("Одно нажатие: проверка GitHub, безопасное обновление исходников, сборка, подпись, установка и запуск на выбранном устройстве.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Собрать локальную версию и установить (\(model.signingMode.title))", systemImage: "hammer.fill") {
                    model.buildLocalChangesAndInstall()
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy || model.selectedDevice == nil || model.repositoryPath.isEmpty || !model.canBuildWithSelectedSigningMode)
                Text("Собирает текущие локальные исходники, подписывает выбранным способом и устанавливает приложение на выбранное устройство. Git pull не выполняется.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Все устройства по Wi‑Fi")
                            .font(.headline)
                        Text("Готово к обновлению: \(model.wirelessReadyDevices.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Обновить все по Wi‑Fi", systemImage: "wifi") {
                        model.updateAllAvailableDevicesOverWiFi()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.repositoryPath.isEmpty || !model.canBuildWithSelectedSigningMode)
                }
                Text("Список обновится автоматически. Для каждого доступного iPhone/iPad установщик по очереди соберёт, подпишет и установит обновление, не открывая приложение без вашей команды.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let device = model.selectedDevice {
                    HStack {
                        Label(
                            device.developerModeEnabled ? "Режим разработчика включён" : "Режим разработчика выключен",
                            systemImage: device.developerModeEnabled ? "checkmark.shield.fill" : "hammer.circle"
                        )
                        .foregroundStyle(device.developerModeEnabled ? Color.green : Color.orange)
                        Spacer()
                        if !device.developerModeEnabled {
                            Button("Включить / инструкция…") {
                                showsDeveloperModeConfirmation = true
                            }
                            .disabled(model.isBusy)
                        }
                    }
                    .font(.caption)
                }
                Divider()
                pathRow(
                    title: "Подписанный IPA",
                    path: model.ipaPath,
                    buttonTitle: "Выбрать…",
                    action: model.chooseIPA
                )
                if let inspection = model.ipaInspection {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Label("\(inspection.version) (\(inspection.build))", systemImage: "checkmark.seal.fill")
                            if let teamName = inspection.teamName {
                                Text(teamName).foregroundStyle(.secondary)
                            }
                        }
                        if let expirationDate = inspection.expirationDate {
                            Text("Подпись действует до \(expirationDate.formatted(date: .long, time: .shortened))")
                                .foregroundStyle(expirationDate.timeIntervalSinceNow < 86_400 ? Color.orange : Color.secondary)
                        }
                    }
                    .font(.caption)
                }
                HStack {
                    Button("Проверить IPA", systemImage: "checkmark.shield") {
                        model.inspectSelectedIPA()
                    }
                    Button("Установить IPA", systemImage: "square.and.arrow.down") {
                        model.installSelectedIPA()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .disabled(model.isBusy || model.selectedDevice == nil || model.ipaPath.isEmpty)

                Divider()
                pathRow(
                    title: "Репозиторий",
                    path: model.repositoryPath,
                    buttonTitle: "Выбрать…",
                    action: model.chooseRepository
                )
            }
            .padding(6)
        }
    }

    private var appleCertCard: some View {
        GroupBox("Подпись AppleCert") {
            VStack(alignment: .leading, spacing: 12) {
                if let status = model.appleCertStatus {
                    LabeledContent("Профиль") { Text(status.profileName) }
                    LabeledContent("Team ID") { Text(status.teamID) }
                    LabeledContent("Действует до") {
                        Text(status.expirationDate.formatted(date: .long, time: .shortened))
                            .foregroundStyle(status.expirationDate <= Date() ? Color.orange : Color.secondary)
                    }
                } else {
                    Text(model.appleCertConfigured
                         ? "Сохранённые данные требуют проверки или замены."
                         : "Сертификат ещё не добавлен. Выберите способ подписи в селекторе выше.")
                        .foregroundStyle(.secondary)
                }
                pathRow(title: "Сертификат .p12", path: model.certificatePath,
                        buttonTitle: "Выбрать…", action: model.chooseAppleCertificate)
                pathRow(title: "Профиль .mobileprovision", path: model.profilePath,
                        buttonTitle: "Выбрать…", action: model.chooseAppleProfile)
                SecureField("Пароль файла .p12", text: $certificatePassword)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(model.appleCertConfigured ? "Заменить AppleCert" : "Сохранить AppleCert") {
                        let password = certificatePassword
                        certificatePassword = ""
                        model.configureAppleCert(password: password)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.certificatePath.isEmpty || model.profilePath.isEmpty)
                    if model.appleCertConfigured {
                        Button("Удалить AppleCert", role: .destructive) { model.removeAppleCert() }
                            .disabled(model.isBusy)
                    }
                }
                Text("Пароль хранится в macOS Keychain; .p12 и профиль — в закрытой папке Application Support. При сборке сертификат импортируется во временную связку ключей, которая удаляется после подписи. Подписанный IPA остаётся доступен в поле выше.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(6)
        }
    }

    private var altServerCard: some View {
        GroupBox("Обновление подписи через AltStore (7 дней)") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("AltServer") { Text(model.altServerDescription) }
                LabeledContent("AltStore Classic") { Text(model.altStoreDescription) }
                HStack {
                    Button("Установить / обновить AltServer", systemImage: "arrow.down.app") {
                        model.prepareAltServer()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Открыть AltServer", systemImage: "menubar.rectangle") {
                        model.launchAltServer()
                    }
                }
                .disabled(model.isBusy)
                Text("Установщик скачает официальный AltServer, проверит подпись и установит его отдельно в «Программы». Загрузка начинается только по этой кнопке.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("1. Подключите устройство по USB, подтвердите доверие. В Finder включите «Показывать этот iPhone/iPad при подключении к Wi‑Fi»; на устройстве включите режим разработчика.")
                Text("2. В значке AltServer в строке меню выберите Install AltStore → ваше устройство. Apple Account, пароль и код 2FA вводите только в AltServer; WooF Installer их не получает и не сохраняет.")
                Text("3. Выберите устройство и IPA, затем нажмите «Передать IPA в AltStore». Установщик скопирует файл через доверенное USB/Wi‑Fi соединение и откроет импорт в AltStore Classic. На устройстве подтвердите установку; Apple Account, пароль и 2FA вводите только в AltStore. Установка через Xcode сама по себе не подключает обновление подписи AltStore.")
                Text("4. Включите фоновое обновление для AltStore в настройках iOS и Background Refresh в AltStore. Mac должен быть включён, AltServer запущен, устройства — в одной сети. Проверьте Refresh All до истечения 7 дней: iOS может отложить фоновую задачу.")
                HStack {
                    Button("Передать IPA в AltStore", systemImage: "iphone.and.arrow.forward") {
                        model.sendIPAtoAltStore()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.ipaPath.isEmpty || model.selectedDevice == nil)
                    Button("Показать IPA в Finder", systemImage: "folder") { model.revealIPAForAltStore() }
                        .disabled(model.isBusy || model.ipaPath.isEmpty)
                    Button("Инструкция AltStore", systemImage: "safari") { model.openAltStoreGuide() }
                }
                Text("Это обновление подписи установленной через AltStore версии. Новую версию WooF.Play нужно импортировать в AltStore отдельно. Автоматическое продление не гарантируется, если Mac или устройство недоступны.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(6)
        }
    }

    private var updatesCard: some View {
        GroupBox("Обновления через GitHub") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Из исходников ветки main").font(.headline)
                        if let count = model.gitBehindCount {
                            Text(count == 0 ? "Обновлений нет" : "Новых коммитов: \(count)")
                                .font(.caption)
                                .foregroundStyle(count == 0 ? Color.secondary : Color.blue)
                        }
                    }
                    Spacer()
                    Button("Проверить Git", systemImage: "arrow.triangle.branch") {
                        model.checkGitUpdates()
                    }
                    Button("Обновить и установить", systemImage: "arrow.down.app") {
                        model.updateFromGitAndInstall()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("Установщик выполняет только fast‑forward обновление. Если в репозитории есть ваши изменения, операция остановится без перезаписи файлов.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Готовый IPA из GitHub Releases").font(.headline)
                        Text(model.releaseDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Проверить релиз", systemImage: "shippingbox") {
                        model.checkGitHubRelease()
                    }
                    Button("Скачать IPA", systemImage: "arrow.down.circle") {
                        model.downloadReleaseIPA()
                    }
                    .disabled(model.githubRelease?.ipaAsset == nil)
                }
                Text("Скачанный пакет проверяется по подписи, bundle ID и контрольной сумме GitHub. Для публичного репозитория рекомендуется публиковать IPA только при осознанном решении: development‑профиль содержит список разрешённых устройств.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TestFlight").font(.headline)
                        Text("Установка без кабеля и Developer Mode · сборка доступна 90 дней")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Вступить в программу", systemImage: "person.badge.plus") {
                        model.openDeveloperEnrollment()
                    }
                    Button("App Store Connect", systemImage: "paperplane") {
                        model.openAppStoreConnect()
                    }
                }
                Text("Текущая семидневная Personal Team‑подпись не поддерживает TestFlight. После активации платной Apple Developer Program используйте ios/scripts/build-testflight-archive.sh и загрузите архив через Xcode Organizer или Xcode Cloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .disabled(model.isBusy)
        }
    }

    private var logCard: some View {
        GroupBox("Технический журнал") {
            ScrollView([.horizontal, .vertical]) {
                Text(model.lastLog)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(minHeight: 90, maxHeight: 220)
        }
    }

    private func pathRow(
        title: String,
        path: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(path.isEmpty ? "не выбрано" : path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
    }
}

private struct DeviceRow: View {
    let device: IOSDevice

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: device.model.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone")
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                Text(device.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !device.developerModeEnabled {
                    Label("Режим разработчика не подтверждён", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
