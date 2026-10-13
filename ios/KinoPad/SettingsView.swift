import SafariServices
import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject private var session: KinoPubSession
    @EnvironmentObject private var library: MediaLibraryStore

    @AppStorage("kinoWatchAccountPortal") private var accountPortal = "https://kino.watch"
    @State private var deviceName = ""
    @State private var portalDraft = ""
    @State private var webDestination: AccountWebDestination?
    @State private var showsMirrorInstaller = false
    @State private var portalError: String?
    @State private var pendingDeviceRemoval: KinoPubDevice?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                deviceSection
                devicesSection
                portalSection

                Section("Локальные видео") {
                    LabeledContent("Найдено", value: "\(library.files.count)")
                    LabeledContent("Подключено хранилищ", value: "\(library.sources.filter(\.isAvailable).count)")
                    Text("Файлы во внутренней памяти доступны через «Файлы» → «На моём \(AppDevice.platformName)» → WooF.Play → Movies. Внешний диск подключается в разделе «Офлайн библиотека».")
                        .foregroundStyle(.secondary)
                }

                Section("Совместимость") {
                    Label("MP4, M4V, MOV и совместимые HLS‑потоки воспроизводятся системным AVPlayer.", systemImage: "checkmark.circle")
                    Label("MKV, AVI и редкие кодеки будут подключены через VLC отдельным этапом.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }

                Section("О приложении") {
                    LabeledContent("Приложение", value: "WooF.Play")
                    LabeledContent("Версия", value: "0.3.6")
                    Text("Нативный онлайн‑кинотеатр с каталогом kino.watch и локальной библиотекой.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .task(id: session.isLoggedIn) {
                if session.isLoggedIn { await session.refreshDevices() }
            }
            .onAppear {
                deviceName = session.deviceDisplayName
                portalDraft = accountPortal
            }
            .sheet(item: $webDestination) { destination in
                SafariView(url: destination.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showsMirrorInstaller) {
                MirrorInstallerView(startURL: URL(string: "https://mos-gorsud.site")!) { mirrorURL in
                    accountPortal = mirrorURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    portalDraft = accountPortal
                }
            }
            .alert(
                "Некорректный адрес",
                isPresented: Binding(
                    get: { portalError != nil },
                    set: { if !$0 { portalError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { portalError = nil }
            } message: {
                Text(portalError ?? "Введите адрес персонального зеркала")
            }
            .confirmationDialog(
                pendingDeviceRemoval.map { "Отвязать «\($0.title)»?" } ?? "Отвязать устройство?",
                isPresented: Binding(
                    get: { pendingDeviceRemoval != nil },
                    set: { if !$0 { pendingDeviceRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Отвязать неактивное устройство", role: .destructive) {
                    if let device = pendingDeviceRemoval {
                        Task { await session.removeDevice(device) }
                    }
                    pendingDeviceRemoval = nil
                }
                Button("Отмена", role: .cancel) { pendingDeviceRemoval = nil }
            } message: {
                Text("Перед удалением WooF.Play ещё раз проверит активность. Текущее или недавно активное устройство отвязано не будет.")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Аккаунт kino.watch") {
            LabeledContent("Состояние", value: session.isLoggedIn ? "Выполнен вход" : "Без входа")
            if let account = session.account {
                LabeledContent("Пользователь", value: account.displayName ?? account.username)
                LabeledContent(
                    "Подписка",
                    value: account.subscriptionActive
                        ? "Активна · \(Int(account.subscriptionDays.rounded(.down))) дн."
                        : "Не активна"
                )
                if let end = account.subscriptionEnd {
                    LabeledContent("До", value: end.formatted(date: .long, time: .omitted))
                }
            } else if session.isLoggedIn && session.isLoadingAccount {
                ProgressView("Проверяю профиль и подписку…")
            }

            if session.isLoggedIn {
                HStack {
                    Button("Обновить профиль") { Task { await session.refreshAccount() } }
                        .disabled(session.isLoadingAccount)
                    Spacer()
                    Button("Выйти", role: .destructive) { session.logOut() }
                }
            } else {
                Button("Войти по коду устройства") { session.startLogin() }
                    .disabled(session.isSigningIn)
                if let challenge = session.challenge {
                    LabeledContent("Код", value: challenge.userCode)
                        .font(.headline.monospaced())
                    Button("Открыть страницу активации") { openPortal(path: "device") }
                }
                Button("Создать новый аккаунт") { openPortal(path: "user/register") }
            }
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        Section("Это устройство") {
            TextField("Название устройства", text: $deviceName)
                .textInputAutocapitalization(.words)
            Button {
                Task { await session.updateDeviceDisplayName(deviceName) }
            } label: {
                if session.isUpdatingDevice {
                    ProgressView()
                } else {
                    Label("Сохранить название в kino.watch", systemImage: AppDevice.isPhone ? "iphone.and.arrow.forward" : "ipad.and.arrow.forward")
                }
            }
            .disabled(!session.isLoggedIn || session.isUpdatingDevice || deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("В kino.watch передаются WooF.Play, указанное имя, модель устройства и версия системы.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Открыть управление на сайте") { openPortal(path: "device") }
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        Section("Устройства · безопасное управление") {
            if !session.isLoggedIn {
                Text("Войдите в аккаунт, чтобы увидеть занятые слоты.")
                    .foregroundStyle(.secondary)
            } else if session.isLoadingDevices && session.deviceOverview == nil {
                ProgressView("Проверяю устройства…")
            } else if let overview = session.deviceOverview {
                let activeCount = overview.activeCount()
                LabeledContent("Устройств в слотах", value: "\(overview.slotDevices.count) из \(KinoPubDeviceOverview.slotLimit)")
                LabeledContent("В сети за 15 минут", value: String(activeCount))
                LabeledContent("Свободных слотов", value: String(overview.freeSlotCount))
                if overview.browserCount > 0 {
                    LabeledContent("Браузеры (не занимают слоты)", value: String(overview.browserCount))
                }

                if overview.allSlotsRecentlyActive() {
                    Label(
                        "Все 5 слотов заняты активными устройствами. Безопасная отвязка сейчас недоступна.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else if overview.freeSlotCount == 0 && overview.safelyRemovableCount() == 0 {
                    Label(
                        "Свободных слотов нет, и ни одно устройство нельзя подтвердить как неактивное. Безопасная отвязка недоступна.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .foregroundStyle(.orange)
                } else if overview.freeSlotCount == 0 {
                    Label(
                        "Свободных слотов нет. Можно отвязать только устройство, неактивное более 15 минут.",
                        systemImage: "info.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }

                ForEach(overview.slotDevices) { device in
                    deviceRow(device, overview: overview)
                }
            } else {
                Text("Список устройств пока недоступен.")
                    .foregroundStyle(.secondary)
            }

            if let error = session.deviceManagementError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button {
                Task { await session.refreshDevices() }
            } label: {
                if session.isLoadingDevices {
                    ProgressView()
                } else {
                    Label("Обновить список", systemImage: "arrow.clockwise")
                }
            }
            .disabled(!session.isLoggedIn || session.isLoadingDevices)

            Text("Браузеры не учитываются в пяти слотах и не предлагаются для отвязки. KinoPub отдаёт время последней активности, а не точный онлайн‑статус. Для защиты активным считается устройство, замеченное сервером за последние 15 минут; перед отвязкой статус проверяется повторно.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func deviceRow(_ device: KinoPubDevice, overview: KinoPubDeviceOverview) -> some View {
        let isCurrent = overview.currentDeviceID == device.id
        let isActive = device.isRecentlyActive(within: KinoPubDeviceOverview.activityWindow)
        let canRemove = !isCurrent && device.isSafelyRemovable(activeWithin: KinoPubDeviceOverview.activityWindow)
        let details = [device.hardware, device.software]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCurrent ? AppDevice.storageSystemImage : "display")
                .foregroundStyle(isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.title).font(.subheadline.weight(.semibold))
                if !details.isEmpty {
                    Text(details).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                if let lastSeen = device.lastSeen {
                    HStack(spacing: 4) {
                        Text("Последняя активность")
                        Text(lastSeen, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isCurrent {
                Text("Это устройство")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KinoPadTheme.gold)
            } else if isActive {
                Label("Активно", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if canRemove {
                Button(role: .destructive) {
                    pendingDeviceRemoval = device
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Отвязать \(device.title)")
            } else {
                Text("Статус неизвестен")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var portalSection: some View {
        Section("Персональное зеркало и подписка") {
            TextField("https://ваше-зеркало.example", text: $portalDraft)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            HStack {
                Button("Сохранить зеркало") { savePortal() }
                Spacer()
                Button("Сбросить") {
                    accountPortal = "https://kino.watch"
                    portalDraft = accountPortal
                }
            }
            Button("Получить и установить зеркало") {
                showsMirrorInstaller = true
            }
            Button("Открыть личный кабинет") { openPortal(path: nil) }
            Button("Продлить подписку") { openPortal(path: "donate") }
            Text("Зеркало используется для встроенных страниц регистрации, устройств и оплаты. Каталог и видео работают через API kino.watch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func savePortal() {
        guard let url = normalizedPortalURL(portalDraft) else {
            portalError = "Нужен полный адрес HTTPS с именем домена."
            return
        }
        accountPortal = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        portalDraft = accountPortal
    }

    private func openPortal(path: String?) {
        guard let base = normalizedPortalURL(accountPortal) else {
            portalError = "Сначала проверьте адрес персонального зеркала."
            return
        }
        let url = path.map { base.appendingPathComponent($0) } ?? base
        webDestination = AccountWebDestination(url: url)
    }

    private func normalizedPortalURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }
}

private struct AccountWebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

func normalizedMirrorOrigin(from url: URL, providerHost: String = "mos-gorsud.site") -> URL? {
    guard url.scheme?.lowercased() == "https",
          let host = url.host?.lowercased(),
          !host.isEmpty,
          host != providerHost,
          !host.hasSuffix(".\(providerHost)")
    else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.port = url.port
    return components.url
}

private struct MirrorInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    let startURL: URL
    let onInstall: (URL) -> Void

    @State private var currentURL: URL

    init(startURL: URL, onInstall: @escaping (URL) -> Void) {
        self.startURL = startURL
        self.onInstall = onInstall
        _currentURL = State(initialValue: startURL)
    }

    private var mirrorCandidate: URL? {
        normalizedMirrorOrigin(from: currentURL, providerHost: startURL.host?.lowercased() ?? "mos-gorsud.site")
    }

    var body: some View {
        NavigationStack {
            MirrorWebView(startURL: startURL, currentURL: $currentURL)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let mirrorCandidate {
                            Label(mirrorCandidate.host ?? mirrorCandidate.absoluteString, systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Button {
                                onInstall(mirrorCandidate)
                                dismiss()
                            } label: {
                                Label("Установить это зеркало", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Label(
                                "Войдите в аккаунт и откройте выданную ссылку зеркала. После перехода появится кнопка установки.",
                                systemImage: "safari"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                }
                .navigationTitle("Персональное зеркало")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { dismiss() }
                    }
                }
        }
    }
}

private struct MirrorWebView: UIViewRepresentable {
    let startURL: URL
    @Binding var currentURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MirrorWebView

        init(parent: MirrorWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateCurrentURL(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateCurrentURL(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func updateCurrentURL(from webView: WKWebView) {
            guard let url = webView.url else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.currentURL = url
            }
        }
    }
}
