import SwiftUI
import AppKit

@main
struct ClippyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Clippy", systemImage: "paperclip") {
            ClippyMenu(delegate: delegate)
        }
    }
}

struct ClippyMenu: View {
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
        Button("Выход") { NSApplication.shared.terminate(nil) }
    }
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

    // ponytail: фиксированная длительность показа баллона
    private let bubbleSeconds: Double = 8

    private static let gestures = [
        "Wave", "Congratulate", "GetAttention", "Alert",
        "CheckingSomething", "Explain", "Processing", "Thinking", "Searching",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        runSelfCheckIfRequested()                 // CLIPPY_SELFTEST=1 -> проверка и выход
        NSApp.setActivationPolicy(.accessory)     // agent-приложение, без иконки в доке
        startScheduler()
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
