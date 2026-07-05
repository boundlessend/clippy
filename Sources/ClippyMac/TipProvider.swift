import Foundation

// источник фактов/советов. дальше (P5) появятся Ollama / Claude / RSS / facts-API.
protocol TipProvider {
    func nextTip() async throws -> String
}

// локальный провайдер: читает tips.json из бандла, отдаёт случайный совет
struct LocalJSONProvider: TipProvider {
    private let tips: [String]

    init() throws {
        guard let url = Bundle.module.url(forResource: "tips", withExtension: "json") else {
            throw AssetError.missing("tips.json")
        }
        let list = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        guard !list.isEmpty else { throw AssetError.missing("tips.json (empty)") }
        self.tips = list
    }

    func nextTip() async throws -> String {
        tips.randomElement()!            // непусто по инварианту init
    }
}
