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
        Divider()
        Toggle("Включён", isOn: $settings.enabled)
        Picker("Частота", selection: $settings.intervalMinutes) {
            ForEach(AppSettings.intervalPresets, id: \.self) { Text("\($0) мин").tag($0) }
        }
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
    private var provider: TipProvider?
    private var hideWork: DispatchWorkItem?
    private var monitor: ActivityMonitor?
    private var scheduler: Scheduler?

    // ponytail: длительность показа баллона фиксирована; станет настройкой в P4
    private let bubbleSeconds: Double = 8

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

    // показать скрепыша: Show -> idle-петля, затем баллон с советом, затем спрятать
    func showClippy() {
        if panel == nil { buildPanel() }
        guard let panel, let animator, let provider else { return }
        hideWork?.cancel()
        positionBottomRight(panel)
        panel.orderFrontRegardless()
        animator.play("Show") { [weak animator] in animator?.loop("IdleSideToSide") }

        Task { @MainActor in
            do {
                let tip = try await provider.nextTip()
                self.showBubble(tip, above: panel)
                self.scheduleHide(after: self.bubbleSeconds)
            } catch {
                NSLog("clippy: tip error \(error)")
            }
        }
    }

    private func buildPanel() {
        do {
            let agent = try loadClippyAgent()
            let sheet = try loadSpriteSheet()
            let size = agent.frameSize
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
            imageView.imageScaling = .scaleNone
            self.animator = SpriteAnimator(imageView: imageView, sheet: sheet, agent: agent)
            self.panel = makeOverlayPanel(contentView: imageView, size: size)
            self.provider = try LocalJSONProvider()
        } catch {
            NSLog("clippy: failed to build panel: \(error)")
        }
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
