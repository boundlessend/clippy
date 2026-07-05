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

    @Published var intervalMinutes: Int { didSet { d.set(intervalMinutes, forKey: K.interval) } }
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.enabled) } }
    @Published var showWhenIdle: Bool { didSet { d.set(showWhenIdle, forKey: K.showWhenIdle) } }
    @Published var providerKind: ProviderKind { didSet { d.set(providerKind.rawValue, forKey: K.provider) } }

    private let d = UserDefaults.standard
    private enum K {
        static let interval = "intervalMinutes"
        static let enabled = "enabled"
        static let showWhenIdle = "showWhenIdle"
        static let provider = "providerKind"
    }

    private init() {
        d.register(defaults: [
            K.interval: 10, K.enabled: true, K.showWhenIdle: false,
            K.provider: ProviderKind.local.rawValue,
        ])
        intervalMinutes = d.integer(forKey: K.interval)
        enabled = d.bool(forKey: K.enabled)
        showWhenIdle = d.bool(forKey: K.showWhenIdle)
        providerKind = ProviderKind(rawValue: d.string(forKey: K.provider) ?? "") ?? .local
    }
}
