import AppKit

// следит, активен ли экран: не показываем скрепыша при блокировке, сне дисплея
// или скринсейвере. коннектор к системным уведомлениям.
// strong self в обсерверах намеренно: объект живёт весь сеанс приложения.
@MainActor
final class ActivityMonitor {
    private(set) var screenLocked = false
    private(set) var screenAsleep = false
    private(set) var screensaverActive = false

    var isScreenActive: Bool { !screenLocked && !screenAsleep && !screensaverActive }

    // сколько секунд прошло с последнего ввода пользователя (мышь/клавиатура/скролл).
    // берём минимум по типам событий - это и есть время простоя.
    var secondsSinceUserInput: Double {
        let types: [CGEventType] = [
            .leftMouseDown, .rightMouseDown, .mouseMoved,
            .keyDown, .scrollWheel, .flagsChanged,
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        on(dnc, "com.apple.screenIsLocked") { self.screenLocked = true }
        on(dnc, "com.apple.screenIsUnlocked") { self.screenLocked = false }
        on(dnc, "com.apple.screensaver.didstart") { self.screensaverActive = true }
        on(dnc, "com.apple.screensaver.didstop") { self.screensaverActive = false }

        let wnc = NSWorkspace.shared.notificationCenter
        on(wnc, NSWorkspace.screensDidSleepNotification.rawValue) { self.screenAsleep = true }
        on(wnc, NSWorkspace.screensDidWakeNotification.rawValue) { self.screenAsleep = false }
    }

    private func on(_ center: NotificationCenter, _ name: String,
                    _ action: @escaping @MainActor () -> Void) {
        center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }     // queue .main гарантирует изоляцию
        }
    }
}
