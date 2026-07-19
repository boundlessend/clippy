import Foundation

// сборка провайдеров контента из настроек. вынесено из AppDelegate:
// здесь только настройки и папка активного персонажа, никакого UI и окон

// приоритет полей Ollama: настройка; пустое поле -> дефолт
@MainActor
func resolveOllama(_ s: AppSettings) throws -> (url: URL, model: String) {
    let urlStr = s.ollamaURL.isEmpty ? AppSettings.defaultOllamaURL : s.ollamaURL
    guard let url = URL(string: urlStr) else { throw AssetError.missing("Ollama URL") }
    let model = s.ollamaModel.isEmpty ? AppSettings.defaultOllamaModel : s.ollamaModel
    return (url, model)
}

// ключ Claude: настройка (Keychain); пусто -> env ANTHROPIC_API_KEY (dev-удобство, см. PLAN)
@MainActor
func resolveClaudeKey(_ s: AppSettings) throws -> String {
    let key = s.claudeKey.isEmpty
        ? (ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "") : s.claudeKey
    guard !key.isEmpty else { throw AssetError.missing("ключ Claude (в настройках)") }
    return key
}

// провайдер выбранного источника; local - факты активного персонажа из его tips.json
@MainActor
func makeTipProvider(kind: ProviderKind, settings s: AppSettings,
                     agentDirectory: URL?) throws -> TipProvider {
    switch kind {
    case .local:
        guard let agentDirectory else { throw AssetError.missing("активный персонаж") }
        return try AgentTipsProvider(directory: agentDirectory, enabled: s.enabledCategories)
    case .ollama:
        if s.usePool(for: kind) { return try PoolProvider(character: s.activeAgent) }
        let o = try resolveOllama(s)
        return OllamaProvider(endpoint: o.url, model: o.model,
                              prompt: singleFactPrompt(style: s.ollamaConfig.prompt))
    case .claude:
        if s.usePool(for: kind) { return try PoolProvider(character: s.activeAgent) }
        return ClaudeProvider(apiKey: try resolveClaudeKey(s), maxTokens: max(150, s.claudeConfig.maxLen),
                              prompt: singleFactPrompt(style: s.claudeConfig.prompt))
    case .facts:
        return OnThisDayProvider()
    case .rss:
        guard !s.rssURL.isEmpty, let url = URL(string: s.rssURL) else {
            throw AssetError.missing("адрес RSS (в настройках)")
        }
        return RSSProvider(feedURL: url)
    }
}

// LLM-провайдер для батч-генерации пула: длинный таймаут, одна попытка
// (не гонять долгую и платную генерацию заново)
@MainActor
func makeLLMProvider(kind: ProviderKind, settings s: AppSettings, maxTokens: Int) throws -> LLMProvider {
    switch kind {
    case .ollama:
        let o = try resolveOllama(s)
        return OllamaProvider(endpoint: o.url, model: o.model, timeout: batchTimeout, attempts: 1)
    case .claude:
        return ClaudeProvider(apiKey: try resolveClaudeKey(s), maxTokens: maxTokens,
                              timeout: batchTimeout, attempts: 1)
    default:
        throw AssetError.missing("генерация только для Ollama/Claude")
    }
}
