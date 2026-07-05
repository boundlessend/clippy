import SwiftUI
import AppKit

@main
struct ClippyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Clippy", systemImage: "paperclip") {
            Button("Показать сейчас") { delegate.showClippy() }
            Divider()
            Button("Выход") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var bubblePanel: NSPanel?
    private var animator: SpriteAnimator?
    private var provider: TipProvider?
    private var hideWork: DispatchWorkItem?

    // ponytail: длительность показа баллона фиксирована; станет настройкой в P4
    private let bubbleSeconds: Double = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        runSelfCheckIfRequested()                 // CLIPPY_SELFTEST=1 -> проверка и выход
        NSApp.setActivationPolicy(.accessory)     // agent-приложение, без иконки в доке
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
