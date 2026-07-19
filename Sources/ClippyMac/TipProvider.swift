import Foundation

// источник фактов/советов: локальный, Ollama, Claude, facts-API, RSS
protocol TipProvider: Sendable {
    func nextTip() async throws -> String
}

// факты персонажа из <папка>/tips.json (встроенные Clippy и компания - тоже папки бандла).
// два формата: словарь по категориям (фильтруется включёнными категориями)
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
                // сняты все категории -> throws: showFact объяснит в облачке, а не молчит
                guard !enabled.isEmpty else { throw AssetError.missing("нет включённых категорий фактов") }
                let filtered = byCategory.filter { enabled.contains($0.key) }.flatMap(\.value)
                // включённые категории не пересеклись с ключами файла -> не молчим, показываем все
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
