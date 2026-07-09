import Foundation

// провайдеры контента из внешних сервисов. общий retry-хелпер и проверка ответа.
// промпт для LLM-провайдеров
let tipPrompt = "Дай один короткий интересный факт или полезный совет на русском языке. "
    + "Одно-два предложения, без вступления и без кавычек."

struct HTTPError: Error { let status: Int }

// таймаут внешних запросов
let networkTimeout: TimeInterval = 15

// эфемерная сессия для провайдеров: без дискового кэша запросов/ответов
let tipSession = URLSession(configuration: .ephemeral)

// проверка HTTP-ответа. тело ответа не логируем: оно контролируется эндпоинтом и
// может утечь в системный лог, поэтому храним только статус
func ensureOK(_ resp: URLResponse, _ data: Data) throws {
    guard let http = resp as? HTTPURLResponse else { throw HTTPError(status: -1) }
    guard (200..<300).contains(http.statusCode) else { throw HTTPError(status: http.statusCode) }
}

// retries с warning-логами, затем raise последней ошибки (правило проекта).
// клиентские 4xx (напр. 401 при неверном ключе) не ретраим - бесполезно
func withRetries<T>(_ attempts: Int = 3, _ op: () async throws -> T) async throws -> T {
    var last: Error?
    for i in 1...attempts {
        do { return try await op() }
        catch let e as HTTPError where (400..<500).contains(e.status) {
            throw e
        }
        catch {
            last = error
            NSLog("clippy: attempt \(i)/\(attempts) failed: \(error)")
        }
    }
    throw last!
}

// MARK: - Ollama (локальный LLM)

struct OllamaProvider: TipProvider {
    let endpoint: URL
    let model: String

    func nextTip() async throws -> String {
        try await withRetries {
            var req = URLRequest(url: endpoint)
            req.timeoutInterval = networkTimeout
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["model": model, "prompt": tipPrompt, "stream": false]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await tipSession.data(for: req)
            try ensureOK(resp, data)
            let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
            return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
private struct OllamaResponse: Decodable { let response: String }

// MARK: - Claude (Anthropic Messages API)
// при доработке сверить модель/эндпоинт со скиллом claude-api

struct ClaudeProvider: TipProvider {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "claude-haiku-4-5-20251001") {
        self.apiKey = apiKey
        self.model = model
    }

    func nextTip() async throws -> String {
        try await withRetries {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.timeoutInterval = networkTimeout
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 150,
                "messages": [["role": "user", "content": tipPrompt]],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await tipSession.data(for: req)
            try ensureOK(resp, data)
            let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return decoded.content.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
}
private struct ClaudeResponse: Decodable { let content: [Block] }
private struct Block: Decodable { let text: String }

// MARK: - Факты из интернета (публичный JSON API без ключа)

struct FactsAPIProvider: TipProvider {
    func nextTip() async throws -> String {
        try await withRetries {
            let url = URL(string: "https://uselessfacts.jsph.pl/api/v2/facts/random?language=en")!
            var req = URLRequest(url: url)
            req.timeoutInterval = networkTimeout
            let (data, resp) = try await tipSession.data(for: req)
            try ensureOK(resp, data)
            return try JSONDecoder().decode(UselessFact.self, from: data).text
        }
    }
}
private struct UselessFact: Decodable { let text: String }

// MARK: - RSS-лента (заголовок первого элемента)

struct RSSProvider: TipProvider {
    let feedURL: URL

    func nextTip() async throws -> String {
        try await withRetries {
            var req = URLRequest(url: feedURL)
            req.timeoutInterval = networkTimeout
            let (data, resp) = try await tipSession.data(for: req)
            try ensureOK(resp, data)
            guard let title = RSSFirstTitle().parse(data) else {
                throw AssetError.missing("RSS <item><title>")
            }
            return title
        }
    }
}

// минимальный парсер: вытащить <title> первого <item>
private final class RSSFirstTitle: NSObject, XMLParserDelegate {
    private var inItem = false
    private var inTitle = false
    private var buffer = ""
    private var result: String?

    func parse(_ data: Data) -> String? {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if el == "item" { inItem = true }
        if inItem && el == "title" { inTitle = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inTitle { buffer += s }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName: String?) {
        if el == "title" && inTitle {
            result = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            inTitle = false
        }
        if el == "item" { parser.abortParsing() }        // только первый элемент
    }
}
