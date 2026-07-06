import Foundation

// библиотека персонажей: встроенный Clippy + пользовательские из папки Agents.
// каждый пользовательский персонаж - подпапка с agent.json и map.png (+ опц. sounds/).

let builtInAgentName = "Clippy"

// ссылка на персонажа: directory == nil означает встроенного из бандла
struct AgentRef: Identifiable, Equatable {
    let name: String
    let directory: URL?
    var id: String { name }
}

// ~/Library/Application Support/ClippyMac/Agents (создаётся при отсутствии)
func agentsFolder() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("ClippyMac/Agents", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// встроенный Clippy + персонажи из бандла (в комплекте) + пользовательские из папки Agents.
// пользовательская папка с тем же именем перекрывает встроенную в бандл
func discoverAgents() -> [AgentRef] {
    var seen = Set([builtInAgentName])
    var refs = [AgentRef(name: builtInAgentName, directory: nil)]
    let bundled = Bundle.module.url(forResource: "BundledAgents", withExtension: nil)
        .map { validAgents(in: $0) } ?? []
    for ref in validAgents(in: agentsFolder()) + bundled where seen.insert(ref.name).inserted {
        refs.append(ref)
    }
    return refs
}

// валидные подпапки (agent.json + map.png), имя папки = имя персонажа, по алфавиту
private func validAgents(in folder: URL) -> [AgentRef] {
    let fm = FileManager.default
    let subdirs = (try? fm.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return subdirs
        .filter { dir in
            fm.fileExists(atPath: dir.appendingPathComponent("agent.json").path)
                && fm.fileExists(atPath: dir.appendingPathComponent("map.png").path)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { AgentRef(name: $0.lastPathComponent, directory: $0) }
}
