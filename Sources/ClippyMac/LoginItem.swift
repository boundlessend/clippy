import Foundation

// автозапуск через LaunchAgent (без подписи и Xcode, для личного использования).
// ponytail: plist указывает на текущий исполняемый файл; при релизной .app-сборке
// путь надо будет обновить на установленный бинарь

private let loginLabel = "com.clippymac.agent"

private func loginPlistURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(loginLabel).plist")
}

func isLoginItemEnabled() -> Bool {
    FileManager.default.fileExists(atPath: loginPlistURL().path)
}

func setLoginItem(_ enabled: Bool) {
    enabled ? enableLoginItem() : disableLoginItem()
}

private func enableLoginItem() {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let plist: [String: Any] = [
        "Label": loginLabel,
        "ProgramArguments": [exe],
        "RunAtLoad": true,
    ]
    let url = loginPlistURL()
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
        launchctl(["load", url.path])
    } catch {
        NSLog("clippy: login item enable failed: \(error)")
    }
}

private func disableLoginItem() {
    let url = loginPlistURL()
    launchctl(["unload", url.path])
    try? FileManager.default.removeItem(at: url)
}

private func launchctl(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    try? p.run()
    p.waitUntilExit()
}
