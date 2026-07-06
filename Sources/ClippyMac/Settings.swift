import Foundation

// настройки в UserDefaults. общий экземпляр для окна настроек и делегата.
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

    static let tipCategories: [TipCategory] = [
        .init(key: "persona", title: "Про скрепыша"),
        .init(key: "retro", title: "Ретро-техника"),
        .init(key: "history", title: "История техники"),
        .init(key: "internet", title: "Интернет"),
        .init(key: "science", title: "Наука и природа"),
        .init(key: "care", title: "Советы и забота"),
    ]
    static var allCategoryKeys: Set<String> { Set(tipCategories.map(\.key)) }

    // дефолты Ollama (одно место: register-дефолты, init и env-фолбэк в провайдере)
    static let defaultOllamaURL = "http://localhost:11434/api/generate"
    static let defaultOllamaModel = "llama3.2"

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.enabled) } }
    @Published var providerKind: ProviderKind { didSet { d.set(providerKind.rawValue, forKey: K.provider) } }
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

    // активный персонаж (имя): встроенный Clippy или папка из ~/…/ClippyMac/Agents
    @Published var activeAgent: String { didSet { d.set(activeAgent, forKey: K.activeAgent) } }

    private let d = UserDefaults.standard
    private enum K {
        static let enabled = "enabled"
        static let provider = "providerKind"
        static let muted = "muted"
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
        static let rssURL = "rssURL"
        static let claudeKey = "anthropic-api-key"      // account в Keychain
        static let categories = "enabledCategories"
        static let activeAgent = "activeAgent"
    }

    private init() {
        d.register(defaults: [
            K.enabled: true,
            K.provider: ProviderKind.local.rawValue,
            K.muted: true,
            K.ollamaURL: Self.defaultOllamaURL,
            K.ollamaModel: Self.defaultOllamaModel,
            K.rssURL: "",
        ])
        enabled = d.bool(forKey: K.enabled)
        providerKind = ProviderKind(rawValue: d.string(forKey: K.provider) ?? "") ?? .local
        muted = d.bool(forKey: K.muted)
        ollamaURL = d.string(forKey: K.ollamaURL) ?? Self.defaultOllamaURL
        ollamaModel = d.string(forKey: K.ollamaModel) ?? Self.defaultOllamaModel
        rssURL = d.string(forKey: K.rssURL) ?? ""
        claudeKey = Keychain.get(account: K.claudeKey) ?? ""
        enabledCategories = d.stringArray(forKey: K.categories).map(Set.init) ?? Self.allCategoryKeys
        activeAgent = d.string(forKey: K.activeAgent) ?? builtInAgentName
    }
}
