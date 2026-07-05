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
    private var animator: SpriteAnimator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        runSelfCheckIfRequested()                 // CLIPPY_SELFTEST=1 -> проверка и выход
        NSApp.setActivationPolicy(.accessory)     // agent-приложение, без иконки в доке
    }

    // показать скрепыша в правом нижнем углу: Show -> idle-петля
    func showClippy() {
        if panel == nil { buildPanel() }
        guard let panel, let animator else { return }
        positionBottomRight(panel)
        panel.orderFrontRegardless()
        animator.play("Show") { [weak animator] in animator?.loop("IdleSideToSide") }
    }

    private func buildPanel() {
        do {
            let agent = try loadClippyAgent()
            let sheet = try loadSpriteSheet()
            let size = agent.frameSize
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
            imageView.imageScaling = .scaleNone
            self.animator = SpriteAnimator(imageView: imageView, sheet: sheet, agent: agent)
            self.panel = makeClippyPanel(contentView: imageView, size: size)
        } catch {
            NSLog("clippy: failed to load assets: \(error)")
        }
    }
}
