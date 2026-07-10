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
        // сняты все категории -> набор пуст -> throws -> облачко не показываем (не «все»)
        let list = byCategory.filter { enabled.contains($0.key) }.flatMap(\.value)
        guard !list.isEmpty else { throw AssetError.missing("нет включённых категорий фактов") }
        self.tips = list
    }

    func nextTip() async throws -> String {
        guard let tip = tips.randomElement() else { throw AssetError.missing("пустой список фактов") }
        return tip
    }
}

// факты конкретного персонажа из <папка>/tips.json.
// два формата: словарь по категориям (фильтруется включёнными категориями, как у Clippy)
// или плоский массив строк (для своих персонажей - категории необязательны).
// нет файла или пусто -> throws: своих фактов нет, облачко не показываем
struct AgentTipsProvider: TipProvider {
    private let tips: [String]

    init(directory: URL, enabled: Set<String>) throws {
        let url = directory.appendingPathComponent("tips.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AssetError.missing("tips.json персонажа")
        }
        let data = try Data(contentsOf: url)
        let list: [String]
        if let byCategory = try? JSONDecoder().decode([String: [String]].self, from: data) {
            // знакомые ключи -> фильтруем по включённым категориям;
            // чужие ключи (свой персонаж со своими категориями) -> показываем все
            if byCategory.keys.contains(where: AppSettings.allCategoryKeys.contains) {
                let filtered = byCategory.filter { enabled.contains($0.key) }.flatMap(\.value)
                // фильтр обнулил список (тумблеры категорий - про Clippy) -> не молчим, показываем все
                list = filtered.isEmpty ? byCategory.flatMap(\.value) : filtered
            } else {
                list = byCategory.flatMap(\.value)
            }
        } else {
            list = try JSONDecoder().decode([String].self, from: data)
        }
        guard !list.isEmpty else { throw AssetError.missing("tips.json персонажа (пусто)") }
        self.tips = list
    }

    func nextTip() async throws -> String {
        guard let tip = tips.randomElement() else { throw AssetError.missing("пустой список фактов") }
        return tip
    }
}
