import Foundation

// настройки в UserDefaults. общий экземпляр для окна настроек и делегата.
// nonisolated(unsafe) shared: обращаемся только с main-потока
enum ProviderKind: String, CaseIterable, Identifiable {
    case local, ollama, claude, facts, rss
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: "Локальные советы"
        case .ollama: "Ollama (локально)"
        case .claude: "Claude API"
        case .facts: "«В этот день» (Википедия)"
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

// настройки генерации через LLM, свои для каждого провайдера (Ollama, Claude).
// поля persona/constraints/maxLen собирают prompt; prompt редактируется и уходит модели
struct LLMConfig: Codable {
    var persona: String
    var constraints: String
    var maxLen: Int
    var prompt: String       // итоговый промпт-стиль (что уходит модели), редактируемый
    var usePool: Bool        // true: брать из заранее сгенерированного пула; false: живой запрос на клик

    static func makeDefault() -> LLMConfig {
        let persona = "остроумный помощник-скрепыш Clippy"
        let constraints = "Темы: техника, интернет, наука, история, полезные советы."
        let maxLen = 200
        return LLMConfig(persona: persona, constraints: constraints, maxLen: maxLen,
                         prompt: assembleStylePrompt(persona: persona, constraints: constraints, maxLen: maxLen),
                         usePool: false)
    }
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
        .init(key: "humor", title: "Юмор"),
    ]
    static var allCategoryKeys: Set<String> { Set(tipCategories.map(\.key)) }

    // дефолты Ollama (одно место: register-дефолты, init и env-фолбэк в провайдере)
    static let defaultOllamaURL = "http://localhost:11434/api/generate"
    static let defaultOllamaModel = "llama3.2"

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: K.enabled) } }
    @Published var providerKind: ProviderKind {
        didSet {
            d.set(providerKind.rawValue, forKey: K.provider)
            if providerKind == .claude { loadClaudeKeyIfNeeded() }   // ключ читаем лениво (см. claudeKey)
        }
    }
    @Published var muted: Bool { didSet { d.set(muted, forKey: K.muted) } }
    // пауза анимации в доке при включённом режиме энергосбережения (по умолчанию выключено)
    @Published var pauseOnLowPower: Bool { didSet { d.set(pauseOnLowPower, forKey: K.pauseOnLowPower) } }
    // случайный персонаж при каждом запуске (по умолчанию выключено; не перетирает выбор молча)
    @Published var randomAgentOnLaunch: Bool { didSet { d.set(randomAgentOnLaunch, forKey: K.randomAgentOnLaunch) } }
    // кормление файлом отправляет его в Корзину (по умолчанию нет; спрашиваем при первом кормлении)
    @Published var trashOnFeed: Bool { didSet { d.set(trashOnFeed, forKey: K.trashOnFeed) } }
    // спросили ли уже про режим корзины при первом кормлении файлом
    @Published var feedTrashAsked: Bool { didSet { d.set(feedTrashAsked, forKey: K.feedTrashAsked) } }

    // настройки провайдеров (не секреты - в UserDefaults; ключ Claude - в Keychain)
    @Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: K.ollamaURL) } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: K.ollamaModel) } }
    @Published var rssURL: String { didSet { d.set(rssURL, forKey: K.rssURL) } }
    @Published var claudeKey: String {
        didSet {
            guard !suppressClaudeKeyWrite else { return }   // загрузка из Keychain - не перезапись
            let key = claudeKey
            debounceWrite(K.claudeKey) { Keychain.set(key, account: K.claudeKey) }
        }
    }
    private var claudeKeyLoaded = false
    private var suppressClaudeKeyWrite = false

    // однократно прочитать ключ из Keychain, когда он реально нужен (выбран источник Claude).
    // на старте не читаем: при ad-hoc подписи каждая пересборка меняет сигнатуру, и чтение
    // при запуске дёргало бы системный диалог доступа даже у тех, кто Claude не выбирал
    func loadClaudeKeyIfNeeded() {
        guard !claudeKeyLoaded else { return }
        claudeKeyLoaded = true
        suppressClaudeKeyWrite = true
        claudeKey = Keychain.get(account: K.claudeKey) ?? ""
        suppressClaudeKeyWrite = false
    }

    // настройки генерации LLM (промпт-стиль + режим пула), свои для Ollama и Claude
    @Published var ollamaConfig: LLMConfig {
        didSet {
            let c = ollamaConfig
            debounceWrite(K.ollamaConfig) { [weak self] in self?.saveConfig(c, K.ollamaConfig) }
        }
    }
    @Published var claudeConfig: LLMConfig {
        didSet {
            let c = claudeConfig
            debounceWrite(K.claudeConfig) { [weak self] in self?.saveConfig(c, K.claudeConfig) }
        }
    }

    // включённые категории локальных фактов
    @Published var enabledCategories: Set<String> {
        didSet { d.set(Array(enabledCategories), forKey: K.categories) }
    }

    // активный персонаж (имя): встроенный Clippy или папка из ~/…/ClippyMac/Agents
    @Published var activeAgent: String { didSet { d.set(activeAgent, forKey: K.activeAgent) } }

    // режим пула для LLM-источника (false для источников без пула)
    func usePool(for kind: ProviderKind) -> Bool {
        switch kind {
        case .ollama: return ollamaConfig.usePool
        case .claude: return claudeConfig.usePool
        default: return false
        }
    }

    private let d = UserDefaults.standard
    private enum K {
        static let enabled = "enabled"
        static let provider = "providerKind"
        static let muted = "muted"
        static let pauseOnLowPower = "pauseOnLowPower"
        static let randomAgentOnLaunch = "randomAgentOnLaunch"
        static let trashOnFeed = "trashOnFeed"
        static let feedTrashAsked = "feedTrashAsked"
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
        static let rssURL = "rssURL"
        static let claudeKey = "anthropic-api-key"      // account в Keychain
        static let ollamaConfig = "ollamaConfig"        // JSON LLMConfig
        static let claudeConfig = "claudeConfig"        // JSON LLMConfig
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
        pauseOnLowPower = d.bool(forKey: K.pauseOnLowPower)   // по умолчанию false (ключ не задан)
        randomAgentOnLaunch = d.bool(forKey: K.randomAgentOnLaunch)   // по умолчанию false
        trashOnFeed = d.bool(forKey: K.trashOnFeed)                   // по умолчанию false
        feedTrashAsked = d.bool(forKey: K.feedTrashAsked)            // по умолчанию false
        ollamaURL = d.string(forKey: K.ollamaURL) ?? Self.defaultOllamaURL
        ollamaModel = d.string(forKey: K.ollamaModel) ?? Self.defaultOllamaModel
        rssURL = d.string(forKey: K.rssURL) ?? ""
        claudeKey = ""                                       // из Keychain - лениво, см. loadClaudeKeyIfNeeded
        ollamaConfig = Self.loadConfig(d, K.ollamaConfig)
        claudeConfig = Self.loadConfig(d, K.claudeConfig)
        enabledCategories = d.stringArray(forKey: K.categories).map(Set.init) ?? Self.allCategoryKeys
        activeAgent = d.string(forKey: K.activeAgent) ?? builtInAgentName
        if providerKind == .claude { loadClaudeKeyIfNeeded() }   // Claude уже выбран - ключ нужен сразу
    }

    // LLMConfig <-> UserDefaults как JSON; нет/битый -> дефолт
    private func saveConfig(_ c: LLMConfig, _ key: String) {
        do { d.set(try JSONEncoder().encode(c), forKey: key) }
        catch { NSLog("clippy: не удалось сохранить конфиг \(key): \(error)") }
    }
    private static func loadConfig(_ d: UserDefaults, _ key: String) -> LLMConfig {
        guard let data = d.data(forKey: key),
              let c = try? JSONDecoder().decode(LLMConfig.self, from: data) else { return .makeDefault() }
        return c
    }

    // отложенные записи (ключ в Keychain, конфиги в UserDefaults): пишем через 0.5с после
    // последнего изменения, а не на каждый символ ввода; одна очередь на все ключи
    private var pendingWrites: [String: (work: DispatchWorkItem, action: () -> Void)] = [:]

    private func debounceWrite(_ key: String, _ action: @escaping () -> Void) {
        pendingWrites[key]?.work.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWrites[key] = nil
            action()
        }
        pendingWrites[key] = (work, action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // немедленно записать отложенное (напр. при выходе), чтобы не потерять последний ввод
    func flushPendingWrites() {
        let pending = pendingWrites
        pendingWrites.removeAll()
        for entry in pending.values {
            entry.work.cancel()
            entry.action()
        }
    }
}
