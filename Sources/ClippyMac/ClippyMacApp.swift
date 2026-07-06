import SwiftUI
import AppKit

// набор контролов для окна настроек
struct ClippyControls: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("Показать факт") { delegate.showFact() }
        Divider()
        Toggle("Включён", isOn: $settings.enabled)
        Toggle("Звук", isOn: Binding(get: { !settings.muted }, set: { settings.muted = !$0 }))
        Toggle("Запускать при входе", isOn: Binding(
            get: { isLoginItemEnabled() },
            set: { setLoginItem($0) }
        ))
        Divider()
        // источник контента + поля выбранного источника
        Picker("Источник", selection: $settings.providerKind) {
            ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
        }
        providerFields
        if settings.providerKind == .local { categoryToggles }
        Divider()
        // персонаж: встроенный Clippy или папка из ~/…/ClippyMac/Agents
        Picker("Персонаж", selection: $settings.activeAgent) {
            ForEach(delegate.availableAgents) { Text($0.name).tag($0.name) }
        }
        .onChange(of: settings.activeAgent) { _ in delegate.applyAgentChange() }
        HStack {
            Button("Папка персонажей") { delegate.showAgentsFolder() }
            Button("Обновить список") { delegate.reloadAgents() }
        }
        Divider()
        Button("Выход") { NSApplication.shared.terminate(nil) }
    }

    // поля настроек под выбранный источник (ключ Claude - через SecureField)
    @ViewBuilder private var providerFields: some View {
        switch settings.providerKind {
        case .ollama:
            TextField("Адрес Ollama", text: $settings.ollamaURL)
            TextField("Модель Ollama", text: $settings.ollamaModel)
        case .claude:
            SecureField("Ключ Claude API", text: $settings.claudeKey)
        case .rss:
            TextField("Адрес RSS-ленты", text: $settings.rssURL)
        case .local, .facts:
            EmptyView()
        }
    }

    // категории фактов Clippy (действуют для встроенного Clippy + источника «Локальные советы»)
    @ViewBuilder private var categoryToggles: some View {
        Text("Категории фактов").font(.caption).foregroundStyle(.secondary)
        ForEach(AppSettings.tipCategories) { cat in
            Toggle(cat.title, isOn: Binding(
                get: { settings.enabledCategories.contains(cat.key) },
                set: { on in
                    if on { settings.enabledCategories.insert(cat.key) }
                    else { settings.enabledCategories.remove(cat.key) }
                }))
        }
    }
}

// панель настроек для окна
struct SettingsRootView: View {
    let delegate: AppDelegate

    var body: some View {
        Form { ClippyControls(delegate: delegate) }
            .frame(width: 320)
            .frame(maxHeight: 520)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var availableAgents: [AgentRef] = []   // встроенный + из папки
    private var dockView: NSImageView?                // куда рисует аниматор (иконка в доке)
    private var animator: SpriteAnimator?
    private var bubblePanel: NSPanel?                 // облачко с фактом у дока
    private var hideWork: DispatchWorkItem?
    private var settingsWindow: NSWindow?

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // ponytail: фиксированная длительность показа баллона
    private let bubbleSeconds: Double = 8

    private static let gestures = [
        "Wave", "Congratulate", "GetAttention", "Alert",
        "CheckingSomething", "Explain", "Processing", "Thinking", "Searching",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadAgents()                            // список персонажей (встроенный + из папки)
        NSApp.mainMenu = makeMainMenu()           // меню приложения (Cmd+,, Cmd+Q)
        NSApp.setActivationPolicy(.regular)       // всегда в доке
        setupDock()                               // анимированный персонаж в доке
    }

    // левый клик по иконке в доке: показать факт (или сфокусировать открытые настройки)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        } else {
            showFact()
        }
        return true
    }

    // правый клик по иконке в доке: меню (Quit док добавляет сам)
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Показать факт", action: #selector(miFact), keyEquivalent: "")
        m.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: "")
        m.addItem(withTitle: "О программе Clippy", action: #selector(miAbout), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }

    // пересканировать папку персонажей; если активный пропал - вернуться к встроенному
    func reloadAgents() {
        availableAgents = discoverAgents()
        if !availableAgents.contains(where: { $0.name == AppSettings.shared.activeAgent }) {
            AppSettings.shared.activeAgent = builtInAgentName
        }
    }

    // открыть папку персонажей в Finder
    func showAgentsFolder() { NSWorkspace.shared.open(agentsFolder()) }

    // смена персонажа в настройках -> перестроить анимацию в доке
    func applyAgentChange() { rebuildDockAnimator() }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "О программе Clippy", action: #selector(miAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Выход", action: #selector(miQuit), keyEquivalent: "q")
        [about, settings, quit].forEach { $0.target = self }
        return main
    }

    @objc private func miFact() { showFact() }
    @objc private func miSettings() { showSettings() }
    @objc private func miQuit() { NSApp.terminate(nil) }
    @objc private func miAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clippy",
            .applicationVersion: appVersion,
            .credits: NSAttributedString(
                string: "возрождение легендарного скрепыша на macOS",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    // единое окно настроек: из дока и из меню приложения
    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(delegate: self))
            hosting.sizingOptions = []                 // не навязывать окну размер контента
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.contentViewController = hosting
            w.setContentSize(NSSize(width: 340, height: 500))
            w.title = "Настройки Clippy"
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - персонаж в доке

    // активный персонаж: из списка по имени, иначе встроенный
    private func activeAgentRef() -> AgentRef {
        availableAgents.first { $0.name == AppSettings.shared.activeAgent }
            ?? AgentRef(name: builtInAgentName, directory: nil)
    }

    private func setupDock() {
        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        iv.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = iv
        dockView = iv
        rebuildDockAnimator()
    }

    // построить аниматор активного персонажа и запустить бесконечный idle в доке
    private func rebuildDockAnimator() {
        guard let dockView else { return }
        do {
            let ref = activeAgentRef()
            let agent = try loadClippyAgent(from: ref.directory)
            let sheet = try loadSpriteSheet(from: ref.directory)
            let soundsBase = ref.directory?.appendingPathComponent("sounds")
            let a = SpriteAnimator(imageView: dockView, sheet: sheet, agent: agent,
                                   soundsBase: soundsBase,
                                   onRender: { NSApp.dockTile.display() })
            animator = a
            a.play("Show") { [weak a] in a?.loopIdle() }
        } catch {
            NSLog("clippy: failed to build dock animator: \(error)")
        }
    }

    // MARK: - факт в облачке у дока

    // показать факт у иконки в доке; если у персонажа нет фактов - ничего не показываем
    func showFact() {
        guard AppSettings.shared.enabled else { return }
        let anchor = NSEvent.mouseLocation        // курсор сейчас у иконки в доке
        Task { @MainActor in
            guard let tip = await self.fetchTip() else {
                NSLog("clippy: фактов для персонажа нет - облачко не показываем")
                return
            }
            self.hideWork?.cancel()
            self.showBubble(tip, anchor: anchor)
            self.scheduleHide(after: self.bubbleSeconds)
            // короткая реакция персонажа в доке
            self.animator?.play(Self.gestures.randomElement() ?? "Wave") {
                [weak self] in self?.animator?.loopIdle()
            }
        }
    }

    private func showBubble(_ text: String, anchor: NSPoint) {
        let orient = dockOrientation()
        let host = NSHostingView(rootView: SpeechBubbleView(text: text, dock: orient))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        bubblePanel?.orderOut(nil)
        let bp = makeOverlayPanel(contentView: host, size: size)
        bubblePanel = bp

        let visible = NSScreen.main?.visibleFrame ?? .zero
        bp.setFrameOrigin(bubbleOrigin(anchor: anchor, orientation: orient,
                                       bubbleSize: size, screen: visible))
        bp.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.bubblePanel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - контент

    // фолбэк-цепочка: выбранный провайдер, при ошибке - локальные факты персонажа
    private func fetchTip() async -> String? {
        var chain = [AppSettings.shared.providerKind]
        if !chain.contains(.local) { chain.append(.local) }
        for kind in chain {
            do { return try await provider(for: kind).nextTip() }
            catch { NSLog("clippy: провайдер \(kind.rawValue) не сработал: \(error)") }
        }
        return nil
    }

    // локальные факты - по активному персонажу: Clippy -> встроенный tips.json;
    // другой персонаж -> его собственный tips.json (нет файла -> throws -> облачка не будет)
    private func provider(for kind: ProviderKind) throws -> TipProvider {
        let s = AppSettings.shared
        let env = ProcessInfo.processInfo.environment
        switch kind {
        case .local:
            let ref = activeAgentRef()
            if let dir = ref.directory { return try AgentTipsProvider(directory: dir) }
            return try LocalJSONProvider(enabled: s.enabledCategories)
        case .ollama:
            let urlStr = s.ollamaURL.isEmpty
                ? (env["CLIPPY_OLLAMA_URL"] ?? "http://localhost:11434/api/generate") : s.ollamaURL
            guard let url = URL(string: urlStr) else { throw AssetError.missing("Ollama URL") }
            let model = s.ollamaModel.isEmpty ? (env["CLIPPY_OLLAMA_MODEL"] ?? "llama3.2") : s.ollamaModel
            return OllamaProvider(endpoint: url, model: model)
        case .claude:
            let key = s.claudeKey.isEmpty ? (env["ANTHROPIC_API_KEY"] ?? "") : s.claudeKey
            guard !key.isEmpty else { throw AssetError.missing("ключ Claude (в настройках)") }
            return ClaudeProvider(apiKey: key)
        case .facts:
            return FactsAPIProvider()
        case .rss:
            let feed = s.rssURL.isEmpty ? (env["CLIPPY_RSS_URL"] ?? "") : s.rssURL
            guard !feed.isEmpty, let url = URL(string: feed) else {
                throw AssetError.missing("адрес RSS (в настройках)")
            }
            return RSSProvider(feedURL: url)
        }
    }
}
