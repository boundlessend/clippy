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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // agent-приложение: без иконки в доке, но с треем и окнами
        NSApp.setActivationPolicy(.accessory)
    }

    // P0: показать пустую панель в правом нижнем углу, не воруя фокус
    func showClippy() {
        let panel = self.panel ?? makeClippyPanel()
        self.panel = panel
        positionBottomRight(panel)
        panel.orderFrontRegardless()
    }
}
