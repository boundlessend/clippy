import Foundation
import ServiceManagement

// автозапуск через SMAppService (macOS 13+): регистрирует само приложение как объект входа,
// как у обычных приложений (видно в Системных настройках -> Основные -> Объекты входа).
// не запускает вторую копию при включении и не завершает текущую при выключении.
// требует установленного .app (не `swift run`).

func isLoginItemEnabled() -> Bool {
    switch SMAppService.mainApp.status {
    case .enabled, .requiresApproval: return true      // requiresApproval: включено, ждёт подтверждения в Системных настройках
    default: return false
    }
}

// бросает при ошибке регистрации (напр. запуск из исходников, а не установленного .app) -
// вызывающий показывает alert, а не молча откатывает тумблер
func setLoginItem(_ enabled: Bool) throws {
    removeLegacyLaunchAgent()                           // убрать LaunchAgent из прежней реализации
    if enabled {
        if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
    } else {
        if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
    }
}

// после register() система может ждать подтверждения в Системных настройках -> Объекты входа
func loginItemNeedsApproval() -> Bool { SMAppService.mainApp.status == .requiresApproval }
func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

// одноразовая миграция при запуске: если остался LaunchAgent прежней реализации,
// перенести автозапуск на SMAppService (сохранив «включено»), чтобы при входе не плодилась копия
func migrateLegacyLoginItemIfNeeded() {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.clippymac.agent.plist")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? setLoginItem(true)                             // удалит plist и зарегистрирует через SMAppService
}

// удалить LaunchAgent прежней реализации (иначе при входе поднималась вторая копия)
private func removeLegacyLaunchAgent() {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.clippymac.agent.plist")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["unload", url.path]
    try? p.run()
    p.waitUntilExit()
    try? FileManager.default.removeItem(at: url)
}
