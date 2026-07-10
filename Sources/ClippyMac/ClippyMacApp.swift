import SwiftUI
import AppKit

// pure: случайный элемент, по возможности не равный current; nil при пустом списке
func pickRandomOther(from names: [String], current: String) -> String? {
    let others = names.filter { $0 != current }
    return (others.isEmpty ? names : others).randomElement()
}

// pure: порядок опроса провайдеров - выбранный, затем локальный фолбэк (без дублей)
func providerChain(selected: ProviderKind) -> [ProviderKind] {
    selected == .local ? [.local] : [selected, .local]
}

// статичный аватар персонажа: кадр RestPose (иначе первый непустой), обрезанный из спрайтшита
func agentAvatarImage(for ref: AgentRef) -> NSImage? {
    guard let agent = try? loadClippyAgent(from: ref.directory),
          let sheet = try? loadSpriteSheet(from: ref.directory) else { return nil }
    let anim = agent.animations["RestPose"] ?? agent.animations["Idle1_1"]
        ?? agent.animations.values.first
    guard let point = anim?.frames.lazy.compactMap({ $0.images?.first }).first,
          let cg = cropFrame(sheet: sheet, at: point, frameSize: agent.frameSize) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

// окно настроек и его компоненты - в SettingsView.swift (struct SettingsRootView)

// размеры окна настроек - одно место (окно и контент совпадают)
let settingsWidth: CGFloat = 470
let settingsHeight: CGFloat = 640

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    @Published private(set) var availableAgents: [AgentRef] = []   // встроенный + из папки
    @Published private(set) var agentAvatars: [String: NSImage] = [:]   // имя -> аватар (кадр RestPose)
    private var dockView: NSImageView?                // куда рисует аниматор (иконка в доке)
    private var animator: SpriteAnimator?
    private var bubblePanel: NSPanel?                 // облачко с фактом у дока
    private var hideWork: DispatchWorkItem?
    private var settingsWindow: NSWindow?
    private var screenOff = false                    // экран заблокирован или дисплей спит

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // фиксированная длительность показа баллона
    private let bubbleSeconds: Double = 8
    private var gestureInFlight = false               // играет одноразовый жест: idle его не прервёт
    private static let gestureMaxSteps = 60           // потолок кадров жеста (зацикленные не зависнут)

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadAgents()                            // список персонажей (встроенный + из папки)
        // случайный персонаж при старте, если включено в настройках (до setupDock)
        if AppSettings.shared.randomAgentOnLaunch, let name = randomAgentName() {
            AppSettings.shared.activeAgent = name
        }
        NSApp.mainMenu = makeMainMenu()           // меню приложения (Cmd+,, Cmd+Q)
        NSApp.setActivationPolicy(.regular)       // всегда в доке
        setupDock()                               // анимированный персонаж в доке
        setupPowerNotifications()                 // пауза анимации при блокировке/сне экрана
        migrateLegacyLoginItemIfNeeded()          // перенос автозапуска со старого LaunchAgent на SMAppService
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSettings.shared.flushPendingWrites()   // не потерять последний ввод ключа
    }

    // не крутить idle, когда иконка не видна (экран заблокирован или дисплей спит) -
    // экономия CPU/батареи; плюс опциональная пауза в режиме энергосбережения
    private func setupPowerNotifications() {
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(true) }
        }
        dc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(false) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(true) }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.setScreenOff(false) }
        }
        // режим энергосбережения включили/выключили - пересчитать (пауза, если стоит галочка)
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.refreshIdle() }
        }
    }

    // экран погас/зажёгся -> пересчитать, крутить ли idle
    private func setScreenOff(_ off: Bool) {
        screenOff = off
        refreshIdle()
    }

    // idle крутится только при активном экране и без паузы по энергосбережению.
    // единая точка решения: зовётся на блокировку/сон/энергосбережение/смену тумблера
    func refreshIdle() {
        let lowPowerPause = AppSettings.shared.pauseOnLowPower
            && ProcessInfo.processInfo.isLowPowerModeEnabled
        if screenOff || lowPowerPause {
            animator?.stop()
            gestureInFlight = false          // пауза отменяет и текущий жест
        } else if !gestureInFlight {
            animator?.loopIdle()             // играющий жест не рвём: его completion сам вернёт idle
        }
    }

    // левый клик по иконке в доке: показать факт, но если открыто «настоящее» окно
    // (настройки/О программе) - пусть система его поднимет, факт не показываем.
    // облачко (nonactivating-панель, не canBecomeKey) за окно не считаем
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let hasRealWindow = NSApp.windows.contains {
            $0.isVisible && $0 !== bubblePanel && $0.canBecomeKey
        }
        if !hasRealWindow { showFact() }
        return true
    }

    // файлы бросили на иконку в доке: персонаж их «съедает». выключенный Clippy не трогает
    func application(_ application: NSApplication, open urls: [URL]) {
        feed(urls)
    }

    private func feed(_ urls: [URL]) {
        guard AppSettings.shared.enabled, !urls.isEmpty else { return }
        if !AppSettings.shared.feedTrashAsked {               // при первом кормлении спрашиваем один раз
            AppSettings.shared.trashOnFeed = askFeedToTrash()
            AppSettings.shared.feedTrashAsked = true
        }
        playRandomGesture()                                   // реакция персонажа в доке
        let anchor = currentDockAnchor()
        let label = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) файлов"
        guard AppSettings.shared.trashOnFeed else {
            presentBubble("Ням! \(label)", anchor: anchor)    // файлы не трогаем
            return
        }
        // текст показываем по завершении recycle: при ошибке не врём «в Корзину»
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    NSLog("clippy: не удалось отправить в корзину: \(error)")
                    self.presentBubble("Не смог отправить \(label) в Корзину", anchor: anchor)
                } else {
                    self.presentBubble("Ням! \(label) - в Корзину", anchor: anchor)
                }
            }
        }
    }

    // диалог первого кормления: спросить, отправлять ли кормлёные файлы в Корзину
    private func askFeedToTrash() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Кормление файлами"
        alert.informativeText = "Когда вы бросаете файл на иконку Clippy, он его «съедает». "
            + "Отправлять такие файлы в Корзину? Это всегда можно изменить в настройках."
        alert.addButton(withTitle: "Не трогать файлы")       // первая = по умолчанию (безопасно)
        alert.addButton(withTitle: "Отправлять в Корзину")
        return alert.runModal() == .alertSecondButtonReturn
    }


    // правый клик по иконке в доке: меню (Quit док добавляет сам)
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Показать факт", action: #selector(miFact), keyEquivalent: "")
        m.addItem(withTitle: "Показать жест", action: #selector(miGesture), keyEquivalent: "")
        // подменю конкретных жестов активного персонажа
        if let gestures = animator?.gestureNames, !gestures.isEmpty {
            let gItem = NSMenuItem(title: "Жесты", action: nil, keyEquivalent: "")
            let gSub = NSMenu()
            for g in gestures {
                let it = NSMenuItem(title: g, action: #selector(miPlayGesture(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = g
                gSub.addItem(it)
            }
            gItem.submenu = gSub
            m.addItem(gItem)
        }
        m.addItem(.separator())

        // подменю выбора персонажа (галочка на активном) + быстрый рандом
        let agentItem = NSMenuItem(title: "Персонаж", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let active = AppSettings.shared.activeAgent
        for ref in availableAgents {
            let it = NSMenuItem(title: ref.name, action: #selector(miPickAgent(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = ref.name
            it.state = ref.name == active ? .on : .off
            sub.addItem(it)
        }
        agentItem.submenu = sub
        m.addItem(agentItem)
        m.addItem(withTitle: "Случайный персонаж", action: #selector(miRandomAgent), keyEquivalent: "")
        m.addItem(.separator())

        m.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: "")
        m.addItem(withTitle: "О программе Clippy", action: #selector(miAbout), keyEquivalent: "")
        m.items.forEach { $0.target = self }      // топ-уровень; пункты подменю уже с target
        return m
    }

    // пересканировать папку персонажей; если активный пропал - вернуться к встроенному
    func reloadAgents() {
        availableAgents = discoverAgents()
        agentAvatars = Dictionary(
            availableAgents.compactMap { ref in agentAvatarImage(for: ref).map { (ref.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        if !availableAgents.contains(where: { $0.name == AppSettings.shared.activeAgent }) {
            AppSettings.shared.activeAgent = builtInAgentName
            rebuildDockAnimator()          // onChange не сработает на программный сброс
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
        appMenu.addItem(withTitle: "О программе Clippy", action: #selector(miAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Настройки…", action: #selector(miSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Выход", action: #selector(miQuit), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        return main
    }

    @objc private func miFact() { showFact() }
    @objc private func miGesture() { playRandomGesture() }
    @objc private func miSettings() { showSettings() }
    @objc private func miQuit() { NSApp.terminate(nil) }

    // случайный персонаж из меню дока (по возможности не текущий)
    @objc private func miRandomAgent() {
        guard let name = randomAgentName() else { return }
        AppSettings.shared.activeAgent = name
        applyAgentChange()
    }

    // выбор конкретного персонажа из подменю дока
    @objc private func miPickAgent(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              name != AppSettings.shared.activeAgent else { return }
        AppSettings.shared.activeAgent = name
        applyAgentChange()
    }

    // проиграть конкретный жест из подменю «Жесты»
    @objc private func miPlayGesture(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        playGesture(name)
    }
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
                contentRect: NSRect(x: 0, y: 0, width: settingsWidth, height: settingsHeight),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.contentViewController = hosting
            w.setContentSize(NSSize(width: settingsWidth, height: settingsHeight))
            w.minSize = NSSize(width: 380, height: 420)   // не даём окну схлопнуться
            w.title = "Настройки Clippy"
            w.isReleasedWhenClosed = false
            w.delegate = self          // на закрытие отпускаем окно - разрыв retain-цикла
            w.center()
            w.setFrameAutosaveName("ClippySettingsWindow")   // запоминаем размер и позицию между открытиями
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // окно настроек закрыли: отпустить ссылку, иначе граф окна держит delegate (retain-цикл)
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow { settingsWindow = nil }
    }

    // MARK: - персонаж в доке

    // активный персонаж: из списка по имени, иначе встроенный
    private func activeAgentRef() -> AgentRef {
        availableAgents.first { $0.name == AppSettings.shared.activeAgent }
            ?? AgentRef(name: builtInAgentName, directory: nil)
    }

    // имя случайного персонажа, по возможности не текущего; nil - список пуст
    private func randomAgentName() -> String? {
        pickRandomOther(from: availableAgents.map(\.name), current: AppSettings.shared.activeAgent)
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
            animator?.stop()                       // погасить прежний, чтобы не дрались за иконку
            animator = a
            playGesture("Show")                    // приветственный жест, затем idle через гейт
        } catch {
            NSLog("clippy: failed to build dock animator: \(error)")
        }
    }

    // MARK: - факт в облачке у дока

    // проиграть случайный жест активного персонажа
    func playRandomGesture() {
        guard let animator else { return }
        playGesture(animator.gestureNames.randomElement() ?? "Wave")
    }

    // проиграть один жест: пока он идёт, gestureInFlight не даёт refreshIdle его прервать;
    // по завершении снимаем флаг и через гейт возвращаемся в idle
    private func playGesture(_ name: String) {
        guard let animator else { return }
        gestureInFlight = true
        animator.play(name, maxSteps: Self.gestureMaxSteps) { [weak self] in
            guard let self else { return }
            self.gestureInFlight = false
            self.refreshIdle()
        }
    }

    // якорь облачка: точный rect иконки дока через AX, иначе позиция курсора
    private func currentDockAnchor() -> NSPoint {
        dockAnchor(orientation: dockOrientation()) ?? NSEvent.mouseLocation
    }

    // показать облачко у иконки и завести таймер автоскрытия
    private func presentBubble(_ text: String, anchor: NSPoint) {
        showBubble(text, anchor: anchor)
        scheduleHide(after: bubbleSeconds)
    }

    // показать факт у иконки в доке; если у персонажа нет фактов - ничего не показываем
    func showFact() {
        guard AppSettings.shared.enabled else { return }
        // якорь фиксируем в момент клика (курсор потом уедет), показываем после загрузки факта
        let anchor = currentDockAnchor()
        Task { @MainActor in
            guard let tip = await self.fetchTip() else {
                NSLog("clippy: фактов для персонажа нет - облачко не показываем")
                return
            }
            self.presentBubble(tip, anchor: anchor)
            self.playRandomGesture()                        // короткая реакция персонажа в доке
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

        // экран, на котором кликнули (мультимонитор), иначе главный
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
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
        for kind in providerChain(selected: AppSettings.shared.providerKind) {
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
            if let dir = ref.directory { return try AgentTipsProvider(directory: dir, enabled: s.enabledCategories) }
            return try LocalJSONProvider(enabled: s.enabledCategories)
        case .ollama:
            let urlStr = s.ollamaURL.isEmpty
                ? (env["CLIPPY_OLLAMA_URL"] ?? AppSettings.defaultOllamaURL) : s.ollamaURL
            guard let url = URL(string: urlStr) else { throw AssetError.missing("Ollama URL") }
            let model = s.ollamaModel.isEmpty
                ? (env["CLIPPY_OLLAMA_MODEL"] ?? AppSettings.defaultOllamaModel) : s.ollamaModel
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
