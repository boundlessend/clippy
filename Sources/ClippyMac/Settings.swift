import Foundation

// настройки в UserDefaults. общий экземпляр для меню трея и планировщика.
// ponytail: nonisolated(unsafe) shared - осознанно; доступ только с main-потока
enum ProviderKind: String, CaseIterable, Identifiable {
    case local, ollama, claude, facts, rss
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: "Локальные советы"
        case .ollama: "Ollama (локально)"
        case .claude: "Claude API"
        case .facts: "Факты из интернета"
        case .rss: "RSS-лента"
        }
    }
}

final class AppSettings: ObservableObject {
    nonisolated(unsafe) static let shared = AppSettings()

    static let intervalPresets = [5, 10, 15, 30, 60]
    static let scalePresets: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]

    @Published var intervalMinutes: Int { didSet { d.set(intervalMinutes, forKey: K.interval) } }
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.enabled) } }
    @Published var showWhenIdle: Bool { didSet { d.set(showWhenIdle, forKey: K.showWhenIdle) } }
    @Published var providerKind: ProviderKind { didSet { d.set(providerKind.rawValue, forKey: K.provider) } }
    @Published var scale: Double { didSet { d.set(scale, forKey: K.scale) } }
    @Published var muted: Bool { didSet { d.set(muted, forKey: K.muted) } }

    // пауза до момента (epoch-секунды, 0 = нет); позиция скрепыша
    var snoozeUntil: Double { didSet { d.set(snoozeUntil, forKey: K.snooze) } }
    var position: NSPoint? {
        didSet {
            d.set(position != nil, forKey: K.hasPos)
            d.set(Double(position?.x ?? 0), forKey: K.posX)
            d.set(Double(position?.y ?? 0), forKey: K.posY)
        }
    }

    private let d = UserDefaults.standard
    private enum K {
        static let interval = "intervalMinutes"
        static let enabled = "enabled"
        static let showWhenIdle = "showWhenIdle"
        static let provider = "providerKind"
        static let scale = "scale"
        static let muted = "muted"
        static let snooze = "snoozeUntil"
        static let hasPos = "hasPosition"
        static let posX = "posX"
        static let posY = "posY"
    }

    private init() {
        d.register(defaults: [
            K.interval: 10, K.enabled: true, K.showWhenIdle: false,
            K.provider: ProviderKind.local.rawValue,
            K.scale: 1.0, K.muted: true,
        ])
        intervalMinutes = d.integer(forKey: K.interval)
        enabled = d.bool(forKey: K.enabled)
        showWhenIdle = d.bool(forKey: K.showWhenIdle)
        providerKind = ProviderKind(rawValue: d.string(forKey: K.provider) ?? "") ?? .local
        scale = d.double(forKey: K.scale)
        muted = d.bool(forKey: K.muted)
        snoozeUntil = d.double(forKey: K.snooze)
        position = d.bool(forKey: K.hasPos)
            ? NSPoint(x: d.double(forKey: K.posX), y: d.double(forKey: K.posY))
            : nil
    }
}
