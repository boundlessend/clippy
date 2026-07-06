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

// встроенный Clippy + валидные подпапки (имя папки = имя персонажа), по алфавиту
func discoverAgents() -> [AgentRef] {
    let fm = FileManager.default
    let subdirs = (try? fm.contentsOfDirectory(
        at: agentsFolder(), includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles])) ?? []
    let custom = subdirs
        .filter { dir in
            fm.fileExists(atPath: dir.appendingPathComponent("agent.json").path)
                && fm.fileExists(atPath: dir.appendingPathComponent("map.png").path)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { AgentRef(name: $0.lastPathComponent, directory: $0) }
    return [AgentRef(name: builtInAgentName, directory: nil)] + custom
}
