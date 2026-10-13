import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InstallerModel
    @State private var showsDeveloperModeConfirmation = false

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
                LabeledContent("Устройство") {
                    Text(model.selectedDevice?.name ?? "не выбрано")
                }
                LabeledContent("Установлено") {
                    Text(model.installedDescription)
                }
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
                Text("Для нового телефона Xcode автоматически добавит устройство в ваш Apple Developer‑профиль, пересоберёт и подпишет приложение.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Собрать и установить через Xcode", systemImage: "hammer.fill") {
                    model.buildAndInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.selectedDevice == nil || model.repositoryPath.isEmpty)
            }
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
