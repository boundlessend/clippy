import SwiftUI
import AppKit

// набор контролов для окна настроек
struct ClippyControls: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("Показать факт") { delegate.showFact(at: nil) }
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
        Toggle("Иконка в меню-баре", isOn: $settings.showInMenuBar)
            .onChange(of: settings.showInMenuBar) { _ in delegate.updateStatusItem() }
        Toggle("Иконка в доке", isOn: $settings.showInDock)
            .onChange(of: settings.showInDock) { _ in applyActivationPolicy() }
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

    // категории локальных фактов (действуют для источника «Локальные советы»)
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

// иконка в доке = .regular, только трей = .accessory
@MainActor func applyActivationPolicy() {
    NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var availableAgents: [AgentRef] = []   // встроенный + из папки
    private var dockView: NSImageView?                // куда рисует аниматор (иконка в доке)
    private var animator: SpriteAnimator?
    private var bubblePanel: NSPanel?                 // облачко с фактом у дока
    private var localProvider: LocalJSONProvider?     // кеш: читает файл один раз
    private var hideWork: DispatchWorkItem?
    private var builtAgent: String = ""               // имя персонажа, с которым построен аниматор
    private var builtCategories: Set<String> = []     // категории, с которыми построен localProvider
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    // сам скрепыш (с иконки, без фона) для меню-бара; фолбэк - SF-скрепка
    private static let menuBarImage: NSImage = {
        if let url = Bundle.module.url(forResource: "menubar", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            let h: CGFloat = 18
            img.size = NSSize(width: h * img.size.width / img.size.height, height: h)
            return img
        }
        return NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clippy")
            ?? NSImage()
    }()

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
        applyActivationPolicy()                   // док/трей - по настройкам
        updateStatusItem()                        // иконка в баре по настройке
        setupDock()                               // анимированный персонаж в доке
        // если и трей, и док скрыты - показываем окно, иначе в настройки не зайти
        let s = AppSettings.shared
        if !s.showInMenuBar && !s.showInDock { showSettings() }
    }

    // левый клик по иконке в доке: показать факт (или сфокусировать открытые настройки)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
        } else {
            showFact(at: NSEvent.mouseLocation)   // курсор сейчас на иконке в доке
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

    // иконка-скрепыш в меню-баре (опция; по умолчанию выкл, на случай скрытого дока)
    func updateStatusItem() {
        if AppSettings.shared.showInMenuBar {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = Self.menuBarImage
            item.menu = makeStatusMenu()
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Показать факт", action: #selector(miFact), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: ",")
        m.addItem(withTitle: "О программе Clippy", action: #selector(miAbout), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Выход", action: #selector(miQuit), keyEquivalent: "q")
        m.items.forEach { $0.target = self }
        return m
    }

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

    @objc private func miFact() { showFact(at: nil) }
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

    // единое окно настроек: и на первом запуске, и из дока, и из трея
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
            let ref = availableAgents.first { $0.name == AppSettings.shared.activeAgent }
                ?? AgentRef(name: builtInAgentName, directory: nil)
            let agent = try loadClippyAgent(from: ref.directory)
            let sheet = try loadSpriteSheet(from: ref.directory)
            let soundsBase = ref.directory?.appendingPathComponent("sounds")
            let a = SpriteAnimator(imageView: dockView, sheet: sheet, agent: agent,
                                   soundsBase: soundsBase,
                                   onRender: { NSApp.dockTile.display() })
            animator = a
            builtAgent = ref.name
            a.play("Show") { [weak a] in a?.loopIdle() }
        } catch {
            NSLog("clippy: failed to build dock animator: \(error)")
        }
    }

    // MARK: - факт в облачке у дока

    // показать факт: anchor - точка клика в доке (nil -> прикинуть по краю дока)
    func showFact(at anchor: NSPoint?) {
        guard AppSettings.shared.enabled else { return }
        Task { @MainActor in
            guard let tip = await self.fetchTip() else {
                NSLog("clippy: ни один провайдер не дал совет")
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

    private func showBubble(_ text: String, anchor: NSPoint?) {
        let orient = dockOrientation()
        let host = NSHostingView(rootView: SpeechBubbleView(text: text, dock: orient))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        bubblePanel?.orderOut(nil)
        let bp = makeOverlayPanel(contentView: host, size: size)
        bubblePanel = bp

        let screen = NSScreen.main?.frame ?? .zero
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let a = anchor ?? dockEdgeAnchor(orientation: orient, screen: screen)
        bp.setFrameOrigin(bubbleOrigin(anchor: a, orientation: orient, bubbleSize: size, screen: visible))
        bp.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.bubblePanel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - контент

    // фолбэк-цепочка: выбранный провайдер, при ошибке - локальный (он всегда отдаёт факт)
    private func fetchTip() async -> String? {
        var chain = [AppSettings.shared.providerKind]
        if !chain.contains(.local) { chain.append(.local) }
        for kind in chain {
            do { return try await provider(for: kind).nextTip() }
            catch { NSLog("clippy: провайдер \(kind.rawValue) не сработал: \(error)") }
        }
        return nil
    }

    // настройки провайдеров берём из UI (Keychain для ключа Claude), с фолбэком на env
    private func provider(for kind: ProviderKind) throws -> TipProvider {
        let s = AppSettings.shared
        let env = ProcessInfo.processInfo.environment
        switch kind {
        case .local:
            if localProvider == nil || builtCategories != s.enabledCategories {
                localProvider = try LocalJSONProvider(enabled: s.enabledCategories)
                builtCategories = s.enabledCategories
            }
            return localProvider!
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
