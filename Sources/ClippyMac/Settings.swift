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

// категории локальных фактов (ключ совпадает с ключом в tips.json)
struct TipCategory: Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

final class AppSettings: ObservableObject {
    nonisolated(unsafe) static let shared = AppSettings()

    static let scalePresets: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]
    static let tipCategories: [TipCategory] = [
        .init(key: "persona", title: "Про скрепыша"),
        .init(key: "retro", title: "Ретро-техника"),
        .init(key: "history", title: "История техники"),
        .init(key: "internet", title: "Интернет"),
        .init(key: "science", title: "Наука и природа"),
        .init(key: "care", title: "Советы и забота"),
    ]
    static var allCategoryKeys: Set<String> { Set(tipCategories.map(\.key)) }

    // частота показа: произвольное число минут, но не меньше 1
    @Published var intervalMinutes: Int {
        didSet {
            if intervalMinutes < 1 { intervalMinutes = 1; return }
            d.set(intervalMinutes, forKey: K.interval)
        }
    }
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.enabled) } }
    @Published var showWhenIdle: Bool { didSet { d.set(showWhenIdle, forKey: K.showWhenIdle) } }
    @Published var providerKind: ProviderKind { didSet { d.set(providerKind.rawValue, forKey: K.provider) } }
    @Published var scale: Double { didSet { d.set(scale, forKey: K.scale) } }
    @Published var muted: Bool { didSet { d.set(muted, forKey: K.muted) } }

    // настройки провайдеров (не секреты - в UserDefaults; ключ Claude - в Keychain)
    @Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: K.ollamaURL) } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: K.ollamaModel) } }
    @Published var rssURL: String { didSet { d.set(rssURL, forKey: K.rssURL) } }
    @Published var claudeKey: String { didSet { Keychain.set(claudeKey, account: K.claudeKey) } }

    // включённые категории локальных фактов
    @Published var enabledCategories: Set<String> {
        didSet { d.set(Array(enabledCategories), forKey: K.categories) }
    }

    // где показывать приложение (можно скрыть и там, и там; если скрыто всё -
    // окно настроек открывается при запуске уже запущенного приложения)
    @Published var showInMenuBar: Bool { didSet { d.set(showInMenuBar, forKey: K.showInMenuBar) } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: K.showInDock) } }

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
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
        static let rssURL = "rssURL"
        static let claudeKey = "anthropic-api-key"      // account в Keychain
        static let categories = "enabledCategories"
        static let showInMenuBar = "showInMenuBar"
        static let showInDock = "showInDock"
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
            K.ollamaURL: "http://localhost:11434/api/generate",
            K.ollamaModel: "llama3.2",
            K.rssURL: "",
            K.showInMenuBar: true, K.showInDock: true,
        ])
        intervalMinutes = d.integer(forKey: K.interval)
        enabled = d.bool(forKey: K.enabled)
        showWhenIdle = d.bool(forKey: K.showWhenIdle)
        providerKind = ProviderKind(rawValue: d.string(forKey: K.provider) ?? "") ?? .local
        scale = d.double(forKey: K.scale)
        muted = d.bool(forKey: K.muted)
        ollamaURL = d.string(forKey: K.ollamaURL) ?? "http://localhost:11434/api/generate"
        ollamaModel = d.string(forKey: K.ollamaModel) ?? "llama3.2"
        rssURL = d.string(forKey: K.rssURL) ?? ""
        claudeKey = Keychain.get(account: K.claudeKey) ?? ""
        enabledCategories = d.stringArray(forKey: K.categories).map(Set.init) ?? Self.allCategoryKeys
        showInMenuBar = d.bool(forKey: K.showInMenuBar)
        showInDock = d.bool(forKey: K.showInDock)
        snoozeUntil = d.double(forKey: K.snooze)
        position = d.bool(forKey: K.hasPos)
            ? NSPoint(x: d.double(forKey: K.posX), y: d.double(forKey: K.posY))
            : nil
    }
}
