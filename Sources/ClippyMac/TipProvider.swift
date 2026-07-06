import Foundation

// источник фактов/советов: локальный, Ollama, Claude, facts-API, RSS
protocol TipProvider: Sendable {
    func nextTip() async throws -> String
}

// локальный провайдер: читает tips.json (факты по категориям) из бандла,
// оставляет только включённые категории и отдаёт случайный факт
struct LocalJSONProvider: TipProvider {
    private let tips: [String]

    init(enabled: Set<String>) throws {
        guard let url = Bundle.module.url(forResource: "tips", withExtension: "json") else {
            throw AssetError.missing("tips.json")
        }
        let byCategory = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        let chosen = enabled.isEmpty ? Set(byCategory.keys) : enabled
        var list = byCategory.filter { chosen.contains($0.key) }.flatMap(\.value)
        if list.isEmpty { list = byCategory.values.flatMap { $0 } }   // не оставлять пусто
        guard !list.isEmpty else { throw AssetError.missing("tips.json (empty)") }
        self.tips = list
    }

    func nextTip() async throws -> String {
        tips.randomElement()!            // непусто по инварианту init
    }
}
