import Foundation

// провайдеры контента из внешних сервисов. общий retry-хелпер и проверка ответа.
// промпт для LLM-провайдеров по умолчанию (когда пользователь не задал свой стиль)
let tipPrompt = "Дай один короткий интересный факт или полезный совет на русском языке. "
    + "Одно-два предложения, без вступления и без кавычек."

// максимальная длина заголовка RSS в облачке (длиннее - обрезаем по слову)
let rssMaxTitle = 140

struct HTTPError: Error { let status: Int }

// таймаут внешних запросов: обычный (один факт/фид) и для генерации пачки, где
// локальная Ollama с stream:false отдаёт ответ только сгенерив все N фактов
let networkTimeout: TimeInterval = 15
let batchTimeout: TimeInterval = 180

// MARK: - генерация пачкой (наполнение пула) и сборка промпта

// LLM-провайдер: умеет выполнить произвольный промпт (используется и для одного факта, и для пачки)
protocol LLMProvider: Sendable {
    func complete(_ prompt: String) async throws -> String
}

// собрать промпт-стиль из полей: персона (характер), ограничения/темы, максимальная длина.
// описывает стиль фактов, без указания количества - его добавляют single/batch
func assembleStylePrompt(persona: String, constraints: String, maxLen: Int) -> String {
    var parts: [String] = []
    let p = persona.trimmingCharacters(in: .whitespacesAndNewlines)
    let c = constraints.trimmingCharacters(in: .whitespacesAndNewlines)
    if !p.isEmpty { parts.append("Пиши от лица: \(p).") }
    parts.append("Факты короткие и интересные, на русском.")
    if !c.isEmpty { parts.append(c) }
    parts.append("Каждый факт - одно-два предложения, максимум \(maxLen) символов, без нумерации и кавычек.")
    return parts.joined(separator: " ")
}

// живой режим: попросить у модели один факт в заданном стиле
func singleFactPrompt(style: String) -> String {
    style + " Дай один такой факт."
}

// пул: попросить count фактов одним запросом, каждый с новой строки
func batchFactPrompt(style: String, count: Int) -> String {
    style + " Дай \(count) разных таких фактов, каждый с новой строки."
}

// распарсить многострочный ответ модели в отдельные факты:
// снять ведущую нумерацию/маркеры и кавычки, обрезать пробелы, выкинуть пустые.
// нумерация - максимум две цифры: факт, начинающийся с года («1984. …»), не обрезаем.
// строка без маркера и с маленькой буквы - перенесённое продолжение предыдущего факта,
// но только пока предыдущий не закончился предложением: факт, начатый с латиницы
// («iPhone представили…»), к завершённому предыдущему не приклеиваем
func parseFactLines(_ raw: String) -> [String] {
    var out: [String] = []
    for line in raw.split(whereSeparator: \.isNewline) {
        let trimmed = String(line).trimmingCharacters(in: .whitespaces)
        let unmarked = trimmed.replacingOccurrences(
            of: #"^\s*(\d{1,2}[.):]\s*|[-*•]\s*)"#, with: "", options: .regularExpression)
        let hadMarker = unmarked != trimmed
        let s = unmarked.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«»").union(.whitespaces))
        guard !s.isEmpty else { continue }
        let prevEnded = out.last?.last.map { ".!?…".contains($0) } ?? true
        if !hadMarker, s.first?.isLowercase == true, !prevEnded {
            out[out.count - 1] += " " + s
        } else {
            out.append(s)
        }
    }
    return out
}

// сгенерировать пачку фактов одним запросом к модели (для наполнения пула)
func generateFactBatch(_ provider: LLMProvider, style: String, count: Int) async throws -> [String] {
    let raw = try await provider.complete(batchFactPrompt(style: style, count: count))
    let facts = parseFactLines(raw)
    guard !facts.isEmpty else { throw AssetError.missing("модель не вернула фактов") }
    return facts
}

// обрезать длинный заголовок по границе слова, добавить многоточие
func truncateTitle(_ s: String, max: Int) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > max else { return t }
    let clipped = t.prefix(max)
    if let sp = clipped.lastIndex(of: " ") {
        return clipped[..<sp].trimmingCharacters(in: .whitespaces) + "…"
    }
    return clipped + "…"
}

// модель Claude для советов: самая дешёвая/быстрая Haiku; при обновлении сверить со скиллом claude-api
let defaultClaudeModel = "claude-haiku-4-5-20251001"

// эфемерная сессия для провайдеров: без дискового кэша запросов/ответов
let tipSession = URLSession(configuration: .ephemeral)

// потолок тела ответа: кривая лента или эндпоинт не должны съедать память гигабайтами
let maxResponseBytes = 5 * 1024 * 1024

// data(for:) с лимитом размера: читаем поток и обрываем, как только превышен потолок
func fetchLimited(_ req: URLRequest) async throws -> (Data, URLResponse) {
    let (bytes, resp) = try await tipSession.bytes(for: req)
    var data = Data()
    for try await byte in bytes {
        data.append(byte)
        if data.count > maxResponseBytes {
            throw AssetError.missing("ответ больше \(maxResponseBytes / 1024 / 1024) МБ")
        }
    }
    return (data, resp)
}

// проверка HTTP-ответа. тело ответа не логируем: оно контролируется эндпоинтом и
// может утечь в системный лог, поэтому храним только статус
func ensureOK(_ resp: URLResponse) throws {
    guard let http = resp as? HTTPURLResponse else { throw HTTPError(status: -1) }
    guard (200..<300).contains(http.statusCode) else { throw HTTPError(status: http.statusCode) }
}

// retries с warning-логами и нарастающей паузой, затем raise последней ошибки (правило проекта).
// клиентские 4xx (напр. 401 при неверном ключе) не ретраим - бесполезно; 429 (rate limit) - ретраим.
// по умолчанию 2 попытки: каждый nextTip интерактивен (клик по доку), три раза по таймауту
// заставляли ждать облачко до ~45 секунд
func withRetries<T>(_ attempts: Int = 2, _ op: () async throws -> T) async throws -> T {
    var last: Error?
    for i in 1...attempts {
        do { return try await op() }
        catch let e as HTTPError where (400..<500).contains(e.status) && e.status != 429 {
            throw e
        }
        catch is CancellationError {
            throw CancellationError()          // отмену не ретраим и не глотаем
        }
        catch {
            last = error
            NSLog("clippy: attempt \(i)/\(attempts) failed: \(error)")
            // пауза 0.5с, 1.0с…; отмена задачи во время паузы прерывает цикл (не try?)
            if i < attempts { try await Task.sleep(nanoseconds: UInt64(i) * 500_000_000) }
        }
    }
    throw last!
}

// MARK: - Ollama (локальный LLM)

struct OllamaProvider: TipProvider, LLMProvider {
    let endpoint: URL
    let model: String
    var prompt: String = tipPrompt          // промпт для одного факта (nextTip); complete берёт свой
    var timeout: TimeInterval = networkTimeout   // батч поднимает до batchTimeout
    var attempts: Int = 2                        // батч ставит 1: не гонять долгую генерацию заново

    func nextTip() async throws -> String { try await complete(prompt) }

    func complete(_ prompt: String) async throws -> String {
        try await withRetries(attempts) {
            var req = URLRequest(url: endpoint)
            req.timeoutInterval = timeout
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await fetchLimited(req)
            try ensureOK(resp)
            let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
            let text = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AssetError.missing("Ollama вернул пустой ответ") }
            return text
        }
    }
}
private struct OllamaResponse: Decodable { let response: String }

// MARK: - Claude (Anthropic Messages API)
// при доработке сверить модель/эндпоинт со скиллом claude-api

struct ClaudeProvider: TipProvider, LLMProvider {
    let apiKey: String
    let model: String
    let maxTokens: Int
    var prompt: String                       // промпт для одного факта (nextTip); complete берёт свой
    var timeout: TimeInterval                 // батч поднимает до batchTimeout
    var attempts: Int                         // батч ставит 1: не платить за долгий запрос дважды

    init(apiKey: String, model: String = defaultClaudeModel, maxTokens: Int = 150,
         prompt: String = tipPrompt, timeout: TimeInterval = networkTimeout, attempts: Int = 2) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.prompt = prompt
        self.timeout = timeout
        self.attempts = attempts
    }

    func nextTip() async throws -> String { try await complete(prompt) }

    func complete(_ prompt: String) async throws -> String {
        try await withRetries(attempts) {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.timeoutInterval = timeout
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "messages": [["role": "user", "content": prompt]],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await fetchLimited(req)
            try ensureOK(resp)
            let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            var text = (decoded.content.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if decoded.stopReason == "max_tokens" {
                // ответ обрезан посреди строки - обрывок не пускаем в пул/облачко:
                // у батча отбрасываем незавершённую последнюю строку, одиночный ответ - ошибка
                let lines = text.split(whereSeparator: \.isNewline).dropLast()
                guard !lines.isEmpty else { throw AssetError.missing("ответ Claude обрезан по max_tokens") }
                text = lines.joined(separator: "\n")
            }
            guard !text.isEmpty else { throw AssetError.missing("Claude вернул пустой ответ") }
            return text
        }
    }
}
private struct ClaudeResponse: Decodable {
    let content: [Block]
    let stopReason: String?
    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
private struct Block: Decodable { let text: String }

// MARK: - «В этот день» из русской Википедии (события на сегодняшнюю дату, без ключа)

let onThisDayMaxLen = 220

struct OnThisDayProvider: TipProvider {
    func nextTip() async throws -> String {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let mmdd = String(format: "%02d/%02d",
                          cal.component(.month, from: now), cal.component(.day, from: now))
        let ev = try await OnThisDayCache.shared.randomEvent(dateKey: mmdd)
        let base = ev.year.map { "\($0) - \(ev.text)" } ?? ev.text
        let result = truncateTitle(base, max: onThisDayMaxLen)
        guard !result.isEmpty else { throw AssetError.missing("пустое событие") }
        return result
    }

    // весь фид на дату - один сетевой запрос; далее берём из кэша (см. OnThisDayCache)
    static func fetchEvents(mmdd: String) async throws -> [OnThisDayEvent] {
        try await withRetries {
            let url = URL(string: "https://ru.wikipedia.org/api/rest_v1/feed/onthisday/events/\(mmdd)")!
            var req = URLRequest(url: url)
            req.timeoutInterval = networkTimeout
            req.setValue("ClippyMac (macOS dock assistant)", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await fetchLimited(req)
            try ensureOK(resp)
            return try JSONDecoder().decode(OnThisDayResponse.self, from: data).events
        }
    }
}

// кэш событий «В этот день» на текущую дату: не качаем весь фид на каждый клик,
// а держим события дня в памяти (рефетч, когда сменилась дата)
actor OnThisDayCache {
    static let shared = OnThisDayCache()
    private var dateKey = ""
    private var events: [OnThisDayEvent] = []

    func randomEvent(dateKey key: String) async throws -> OnThisDayEvent {
        if key != dateKey || events.isEmpty {
            events = try await OnThisDayProvider.fetchEvents(mmdd: key)
            dateKey = key
        }
        guard let ev = events.randomElement() else { throw AssetError.missing("нет событий на сегодня") }
        return ev
    }
}

struct OnThisDayResponse: Decodable { let events: [OnThisDayEvent] }
struct OnThisDayEvent: Decodable, Sendable { let year: Int?; let text: String }

// MARK: - RSS-лента (заголовок первого элемента)

struct RSSProvider: TipProvider {
    let feedURL: URL

    func nextTip() async throws -> String {
        try await withRetries {
            var req = URLRequest(url: feedURL)
            req.timeoutInterval = networkTimeout
            let (data, resp) = try await fetchLimited(req)
            try ensureOK(resp)
            // случайный из свежих записей: иначе каждый клик показывал бы один и тот же
            // первый заголовок, пока лента не обновится
            guard let title = RSSTitles().parse(data).randomElement() else {
                throw AssetError.missing("RSS <item><title>")
            }
            return truncateTitle(title, max: rssMaxTitle)
        }
    }
}

// минимальный парсер: заголовки первых записей ленты (не более maxItems).
// RSS 2.0 - это <item>, Atom - <entry>; поддерживаем оба (иначе Atom молча падал в фолбэк).
// заголовок в <![CDATA[...]]> XMLParser отдаёт колбэком foundCDATA, а не foundCharacters -
// без него такие ленты (часть WordPress/новостных) молча падали в локальный фолбэк.
// не private: логику гоняет selftest
final class RSSTitles: NSObject, XMLParserDelegate {
    static let maxItems = 10              // хватает для «случайного свежего», дальше не парсим
    private var inItem = false
    private var inTitle = false
    private var buffer = ""
    private var titles: [String] = []

    private static func isEntry(_ el: String) -> Bool { el == "item" || el == "entry" }

    func parse(_ data: Data) -> [String] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return titles
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if Self.isEntry(el) { inItem = true }
        if inItem && el == "title" { inTitle = true; buffer = "" }   // title до записи (заголовок ленты) пропускаем
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inTitle { buffer += s }
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if inTitle { buffer += String(data: block, encoding: .utf8) ?? "" }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName: String?) {
        if el == "title" && inTitle {
            let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { titles.append(t) }
            inTitle = false
        }
        if Self.isEntry(el) {
            inItem = false
            if titles.count >= Self.maxItems { parser.abortParsing() }
        }
    }
}
