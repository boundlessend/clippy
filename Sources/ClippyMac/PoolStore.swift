import Foundation

// пул заранее сгенерированных фактов на персонажа: JSON-массив строк в Application Support.
// заполняется пачками через Ollama/Claude, читается мгновенно по клику (без прогрева и оплаты)
enum PoolStore {
    static let maxPool = 500                 // потолок пула: держим новейшие N, старое вытесняется

    // ~/Library/Application Support/ClippyMac/pools (папку создаём при обращении)
    static func poolsDir() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ClippyMac/pools", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // ~/Library/Application Support/ClippyMac/pools/<персонаж>.json
    static func url(character: String) throws -> URL {
        try poolsDir().appendingPathComponent(sanitize(character) + ".json")
    }

    static func load(character: String) -> [String] {
        guard let u = try? url(character: character),
              let data = try? Data(contentsOf: u),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    // дописать пачку к пулу, убрав дубли и сохранив порядок; при переполнении держим новейшие
    static func append(character: String, facts: [String]) throws {
        let merged = orderedUnique(load(character: character) + facts)
        let capped = merged.count > maxPool ? Array(merged.suffix(maxPool)) : merged
        // .atomic: при падении в момент записи файл пула не останется усечённым/битым
        try JSONEncoder().encode(capped).write(to: url(character: character), options: .atomic)
    }

    static func clear(character: String) throws {
        try FileManager.default.removeItem(at: url(character: character))
    }

    static func count(character: String) -> Int { load(character: character).count }

    // удалить пулы персонажей, которых больше нет в библиотеке (осиротевшие файлы)
    static func prune(keeping names: Set<String>) {
        guard let dir = try? poolsDir(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return }
        let keep = Set(names.map(sanitize))
        for f in files where f.pathExtension == "json"
            && !keep.contains(f.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    // безопасное имя файла: убираем разделители пути и управляющие, юникод-буквы оставляем
    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:.").union(.controlCharacters)
        let s = String(name.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) })
        return s.isEmpty ? "default" : s
    }
}

// сохранить порядок, выкинуть повторы
func orderedUnique(_ xs: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for x in xs where seen.insert(x).inserted { out.append(x) }
    return out
}

// провайдер из пула: случайный факт; пусто -> throws (сработает фолбэк на локальные)
struct PoolProvider: TipProvider {
    private let tips: [String]

    init(character: String) throws {
        let list = PoolStore.load(character: character)
        guard !list.isEmpty else { throw AssetError.missing("пул фактов пуст") }
        tips = list
    }

    func nextTip() async throws -> String {
        guard let t = tips.randomElement() else { throw AssetError.missing("пустой пул") }
        return t
    }
}
