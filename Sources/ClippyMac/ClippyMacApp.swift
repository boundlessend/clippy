import SwiftUI
import AppKit

// общий набор контролов для окна настроек
struct ClippyControls: View {
    let delegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("Показать сейчас") { delegate.showClippy() }
        Button("Проиграть жест") { delegate.playGesture() }
        Divider()
        Toggle("Включён", isOn: $settings.enabled)
        Picker("Частота", selection: $settings.intervalMinutes) {
            ForEach(AppSettings.intervalPresets, id: \.self) { Text("\($0) мин").tag($0) }
        }
        Picker("Размер", selection: $settings.scale) {
            ForEach(AppSettings.scalePresets, id: \.self) { Text(String(format: "×%g", $0)).tag($0) }
        }
        Picker("Источник", selection: $settings.providerKind) {
            ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Звук", isOn: Binding(get: { !settings.muted }, set: { settings.muted = !$0 }))
        Toggle("Показывать при простое", isOn: $settings.showWhenIdle)
        Toggle("Запускать при входе", isOn: Binding(
            get: { isLoginItemEnabled() },
            set: { setLoginItem($0) }
        ))
        Divider()
        Toggle("Показывать в меню-баре", isOn: $settings.showInMenuBar)
            .onChange(of: settings.showInMenuBar) { _ in delegate.updateStatusItem() }
        Toggle("Показывать в доке", isOn: $settings.showInDock)
            .onChange(of: settings.showInDock) { _ in applyActivationPolicy() }
        Divider()
        Button("Выход") { NSApplication.shared.terminate(nil) }
    }
}

// компактная панель настроек: и как выпадашка из трея, и как фолбэк-окно
struct SettingsRootView: View {
    let delegate: AppDelegate

    var body: some View {
        Form { ClippyControls(delegate: delegate) }
            .frame(width: 280)
            .frame(maxHeight: 460)
    }
}

// иконка в доке = .regular, только трей = .accessory
@MainActor func applyActivationPolicy() {
    NSApp.setActivationPolicy(AppSettings.shared.showInDock ? .regular : .accessory)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var bubblePanel: NSPanel?
    private var animator: SpriteAnimator?
    private var localProvider: LocalJSONProvider?     // кеш: читает файл один раз
    private var hideWork: DispatchWorkItem?
    private var monitor: ActivityMonitor?
    private var scheduler: Scheduler?
    private var builtScale: Double = 0                // масштаб, с которым построена панель
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
        NSApp.mainMenu = makeMainMenu()           // меню приложения (док-режим, Cmd+,, Cmd+Q)
        applyActivationPolicy()                   // док/трей - по настройкам
        updateStatusItem()                        // иконка в баре по настройке
        startScheduler()
        // если и трей, и док скрыты - показываем окно, иначе в настройки не зайти
        let s = AppSettings.shared
        if !s.showInMenuBar && !s.showInDock { showSettings() }
    }

    // клик по иконке в доке (нет открытых окон) - открыть настройки
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSettings() }
        return true
    }

    // иконка-скрепыш в меню-баре с выпадающим меню (создаём/убираем по настройке)
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
        m.addItem(withTitle: "Показать сейчас", action: #selector(miShow), keyEquivalent: "")
        m.addItem(withTitle: "Проиграть жест", action: #selector(miGesture), keyEquivalent: "")
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

    @objc private func miShow() { showClippy() }
    @objc private func miGesture() { playGesture() }
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
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 430),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.contentViewController = hosting
            w.setContentSize(NSSize(width: 300, height: 430))
            w.title = "Настройки Clippy"
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func startScheduler() {
        let env = ProcessInfo.processInfo.environment
        let firstDelay = env["CLIPPY_FIRST_DELAY_SEC"].flatMap(Double.init) ?? 30
        let idleThreshold: Double = 120           // не беспокоить, если юзер отошёл дольше

        let monitor = ActivityMonitor()
        self.monitor = monitor
        let scheduler = Scheduler(
            firstDelaySeconds: firstDelay,
            baseInterval: {
                // CLIPPY_INTERVAL_SEC - отладочный override частоты из настроек
                if let e = env["CLIPPY_INTERVAL_SEC"].flatMap(Double.init) { return e }
                return Double(AppSettings.shared.intervalMinutes * 60)
            },
            isAllowed: { [weak self] in
                guard let self, let m = self.monitor else { return false }
                guard AppSettings.shared.enabled, m.isScreenActive else { return false }
                if AppSettings.shared.snoozeUntil > Date().timeIntervalSince1970 { return false }
                if !AppSettings.shared.showWhenIdle && m.secondsSinceUserInput > idleThreshold {
                    return false
                }
                return true
            },
            action: { [weak self] in self?.showClippy() }
        )
        self.scheduler = scheduler
        scheduler.start()
    }

    // сперва получаем совет, затем показываем скрепыша: без совета не всплываем
    func showClippy() {
        if panel == nil || builtScale != AppSettings.shared.scale { rebuildPanel() }
        guard let panel, let animator else { return }

        Task { @MainActor in
            let tip: String
            do {
                tip = try await self.provider(for: AppSettings.shared.providerKind).nextTip()
            } catch {
                NSLog("clippy: tip error \(error)")
                return
            }
            self.hideWork?.cancel()
            self.positionPanel(panel)
            panel.orderFrontRegardless()
            animator.play("Show") { [weak animator] in animator?.loopIdle() }
            self.showBubble(tip, above: panel)
            self.scheduleHide(after: self.bubbleSeconds)
        }
    }

    // проиграть случайный жест (если скрепыш скрыт - сперва показать с советом)
    func playGesture() {
        guard let panel, panel.isVisible, let animator else { showClippy(); return }
        hideWork?.cancel()
        let gesture = Self.gestures.randomElement() ?? "Wave"
        animator.play(gesture) { [weak animator] in animator?.loopIdle() }
        scheduleHide(after: bubbleSeconds)
    }

    private func provider(for kind: ProviderKind) throws -> TipProvider {
        let env = ProcessInfo.processInfo.environment
        switch kind {
        case .local:
            if localProvider == nil { localProvider = try LocalJSONProvider() }
            return localProvider!
        case .ollama:
            let url = URL(string: env["CLIPPY_OLLAMA_URL"] ?? "http://localhost:11434/api/generate")!
            return OllamaProvider(endpoint: url, model: env["CLIPPY_OLLAMA_MODEL"] ?? "llama3.2")
        case .claude:
            return try ClaudeProvider()
        case .facts:
            return FactsAPIProvider()
        case .rss:
            guard let s = env["CLIPPY_RSS_URL"], let url = URL(string: s) else {
                throw AssetError.missing("CLIPPY_RSS_URL (env)")
            }
            return RSSProvider(feedURL: url)
        }
    }

    private func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil
        animator = nil
        buildPanel()
    }

    private func buildPanel() {
        do {
            let agent = try loadClippyAgent()
            let sheet = try loadSpriteSheet()
            let scale = AppSettings.shared.scale
            let base = agent.frameSize
            let size = NSSize(width: base.width * scale, height: base.height * scale)

            let imageView = ClippyImageView(frame: NSRect(origin: .zero, size: size))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.onClick = { [weak self] in self?.playGesture() }
            imageView.menu = makeContextMenu()

            self.animator = SpriteAnimator(imageView: imageView, sheet: sheet, agent: agent)
            let p = makeOverlayPanel(contentView: imageView, size: size)
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: p, queue: .main
            ) { [weak p] _ in
                MainActor.assumeIsolated { if let p { AppSettings.shared.position = p.frame.origin } }
            }
            self.panel = p
            self.builtScale = scale
        } catch {
            NSLog("clippy: failed to build panel: \(error)")
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        if let pos = AppSettings.shared.position {
            panel.setFrameOrigin(pos)
        } else {
            positionBottomRight(panel)
        }
    }

    private func makeContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Следующий совет", action: #selector(ctxNextTip), keyEquivalent: "")
        m.addItem(withTitle: "Проиграть жест", action: #selector(ctxGesture), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Спрятать", action: #selector(ctxHide), keyEquivalent: "")
        m.addItem(withTitle: "Заткнуть на час", action: #selector(ctxSnooze), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }

    @objc private func ctxNextTip() { showClippy() }
    @objc private func ctxGesture() { playGesture() }
    @objc private func ctxHide() { hideClippy() }
    @objc private func ctxSnooze() {
        AppSettings.shared.snoozeUntil = Date().timeIntervalSince1970 + 3600
        hideClippy()
    }

    private func showBubble(_ text: String, above clippyPanel: NSPanel) {
        let host = NSHostingView(rootView: SpeechBubbleView(text: text))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        bubblePanel?.orderOut(nil)
        let bp = makeOverlayPanel(contentView: host, size: size)
        bubblePanel = bp

        let cf = clippyPanel.frame
        bp.setFrameOrigin(NSPoint(x: cf.midX - size.width / 2, y: cf.maxY + 4))
        bp.orderFrontRegardless()
    }

    private func scheduleHide(after seconds: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideClippy() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func hideClippy() {
        bubblePanel?.orderOut(nil)
        animator?.play("Hide") { [weak self] in self?.panel?.orderOut(nil) }
    }
}
