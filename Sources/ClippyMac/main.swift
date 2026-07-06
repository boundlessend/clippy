import AppKit

// точка входа: сперва возможный self-check (без запуска GUI, дружит с headless CI),
// затем само приложение на чистом AppKit (NSStatusItem надёжнее SwiftUI MenuBarExtra)
runSelfCheckIfRequested()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    _ = delegate                     // держим ссылку: NSApplication.delegate - weak
    app.run()
}
