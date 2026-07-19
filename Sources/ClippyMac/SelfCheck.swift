import Foundation
import AppKit

// проверка логики без GUI: парсинг agent.json и кроп каждого кадра.
// запуск: CLIPPY_SELFTEST=1 swift run
func runSelfCheckIfRequested() {
    guard ProcessInfo.processInfo.environment["CLIPPY_SELFTEST"] != nil else { return }
    do {
        let agent = try loadClippyAgent(from: nil)
        precondition(agent.framesize.count == 2, "framesize must be [w,h]")
        let fs = agent.frameSize
        precondition(fs.width > 0 && fs.height > 0, "empty frame size")

        let sheet = try loadSpriteSheet(from: nil)
        var cropped = 0
        for (name, anim) in agent.animations {
            for frame in anim.frames {
                guard let point = frame.images?.first else { continue }
                guard let cg = cropFrame(sheet: sheet, at: point, frameSize: fs) else {
                    fatalError("crop returned nil for \(name) at \(point)")
                }
                precondition(cg.width == Int(fs.width) && cg.height == Int(fs.height),
                             "out-of-bounds crop for \(name) at \(point)")
                cropped += 1
                break                                  // хватит первого непустого кадра
            }
        }
        // контент: tips.json грузится, непустой, и провайдер инициализируется
        guard let turl = resourceBundle.url(forResource: "tips", withExtension: "json") else {
            fatalError("tips.json missing")
        }
        let byCat = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: turl))
        let tips = byCat.values.flatMap { $0 }
        precondition(!tips.isEmpty && tips.allSatisfy { !$0.isEmpty }, "tips must be non-empty")
        precondition(AppSettings.allCategoryKeys.isSubset(of: Set(byCat.keys)),
                     "tips.json missing a category")
        _ = try LocalJSONProvider(enabled: AppSettings.allCategoryKeys)

        // облачко у дока: origin всегда внутри экрана и с нужной стороны от иконки
        let vf = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let bsize = NSSize(width: 200, height: 60)
        let anchor = NSPoint(x: 700, y: 40)
        for orient in [DockOrientation.bottom, .left, .right] {
            let p = bubbleOrigin(anchor: anchor, orientation: orient, bubbleSize: bsize, screen: vf)
            precondition(p.x >= vf.minX + 4 && p.x <= vf.maxX - bsize.width - 4
                         && p.y >= vf.minY + 4 && p.y <= vf.maxY - bsize.height - 4,
                         "bubble out of bounds for \(orient)")
        }
        precondition(bubbleOrigin(anchor: anchor, orientation: .bottom,
                                  bubbleSize: bsize, screen: vf).y >= anchor.y,
                     "bottom-dock bubble must sit above the click")

        // якорь берётся с края иконки, обращённого к доку (низ -> верх, слева -> правый край, справа -> левый)
        let icon = NSRect(x: 100, y: 200, width: 60, height: 60)
        precondition(dockEdgeAnchor(iconRect: icon, orientation: .bottom) == NSPoint(x: icon.midX, y: icon.maxY),
                     "bottom anchor must be top-center of icon")
        precondition(dockEdgeAnchor(iconRect: icon, orientation: .left) == NSPoint(x: icon.maxX, y: icon.midY),
                     "left anchor must be right-center of icon")
        precondition(dockEdgeAnchor(iconRect: icon, orientation: .right) == NSPoint(x: icon.minX, y: icon.midY),
                     "right anchor must be left-center of icon")

        // жесты персонажа: список содержит реальные жесты, но не idle/look/служебные
        let gestures = Set(expressiveGestures(from: Array(agent.animations.keys)))
        precondition(gestures.contains("Wave") && gestures.contains("Congratulate"),
                     "expressiveGestures must include real gestures")
        precondition(gestures.isDisjoint(with: ["Idle1_1", "LookUp", "RestPose", "Show", "Hide"]),
                     "expressiveGestures must exclude idle/look/service anims")

        // случайный персонаж: по возможности не текущий; единственный - возвращает себя
        precondition(pickRandomOther(from: ["a"], current: "a") == "a", "single element returns itself")
        precondition(pickRandomOther(from: ["a", "b"], current: "a") == "b", "excludes current when possible")
        precondition(pickRandomOther(from: [], current: "a") == nil, "empty list -> nil")
        // фолбэк-цепочка провайдеров: local сам по себе, иначе выбранный + local
        precondition(providerChain(selected: .local) == [.local], "local chain is just local")
        precondition(providerChain(selected: .claude) == [.claude, .local], "remote chain falls back to local")

        // библиотека персонажей: встроенный Clippy всегда доступен и грузится как из папки=nil
        let agents = discoverAgents()
        precondition(agents.contains { $0.name == builtInAgentName && $0.directory == nil },
                     "built-in agent missing from library")
        _ = try loadClippyAgent(from: nil)

        // факты персонажей: у кого есть свой tips.json - грузится и непустой (проверяет dict+flat)
        var agentTipsChecked = 0
        for ref in agents {
            guard let dir = ref.directory,
                  FileManager.default.fileExists(atPath: dir.appendingPathComponent("tips.json").path)
            else { continue }
            _ = try AgentTipsProvider(directory: dir, enabled: AppSettings.allCategoryKeys)
            agentTipsChecked += 1
        }

        // branching/exitBranch: все целевые индексы в границах своей анимации
        var soundKeys = Set<String>()
        for (name, anim) in agent.animations {
            let n = anim.frames.count
            for f in anim.frames {
                for br in f.branching?.branches ?? [] {
                    precondition(br.frameIndex >= 0 && br.frameIndex < n,
                                 "branch index out of range in \(name)")
                }
                if let e = f.exitBranch {
                    precondition(e >= 0 && e < n, "exitBranch out of range in \(name)")
                }
                if let s = f.sound { soundKeys.insert(s) }
            }
            if n > 0 {
                let ni = nextFrameIndex(current: 0, frames: anim.frames)
                precondition(ni >= 0 && ni <= n, "next index invalid in \(name)")
            }
        }
        // звуки: каждый ключ из кадров есть в бандле
        for key in soundKeys {
            precondition(
                resourceBundle.url(forResource: key, withExtension: "mp3") != nil,
                "missing sound \(key).mp3")
        }

        // генерация пула: парсинг ответа модели, сборка промпта, обрезка RSS, имя файла пула
        let parsed = parseFactLines("1. Первый факт\n- Второй факт\n\n  \"Третий факт\"  \n")
        precondition(parsed == ["Первый факт", "Второй факт", "Третий факт"], "parseFactLines: \(parsed)")
        precondition(parseFactLines("1984. Выпущен Macintosh") == ["1984. Выпущен Macintosh"],
                     "год в начале факта - не нумерация списка")
        precondition(parseFactLines("Начало факта,\nа это его продолжение")
                     == ["Начало факта, а это его продолжение"], "перенос строки склеивается")
        precondition(parseFactLines("1. факт раз\n2. факт два").count == 2,
                     "нумерованные строки - отдельные факты, даже с маленькой буквы")
        precondition(assembleStylePrompt(persona: "Клиппи", constraints: "", maxLen: 100).contains("Клиппи"),
                     "style prompt must include persona")
        precondition(batchFactPrompt(style: "S", count: 5).contains("5"), "batch prompt must include count")
        precondition(truncateTitle("абв где ёжз", max: 6) == "абв…", "truncateTitle word boundary")
        precondition(truncateTitle("коротко", max: 100) == "коротко", "short title unchanged")
        precondition(orderedUnique(["a", "b", "a", "c"]) == ["a", "b", "c"], "orderedUnique keeps first order")
        precondition(PoolStore.sanitize("../evil/Клип:пи") == "___evil_Клип_пи", "pool name must strip path chars")

        // RSS-парсер: заголовок ленты пропускаем, CDATA читаем, несколько записей собираем
        let rssXML = """
        <rss><channel><title>Лента</title>
        <item><title><![CDATA[Заголовок в CDATA]]></title></item>
        <item><title>Обычный заголовок</title></item>
        </channel></rss>
        """
        let rssTitles = RSSTitles().parse(Data(rssXML.utf8))
        precondition(rssTitles == ["Заголовок в CDATA", "Обычный заголовок"], "rss titles: \(rssTitles)")
        let atomXML = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Фид</title>
        <entry><title>Атом-заголовок</title></entry></feed>
        """
        precondition(RSSTitles().parse(Data(atomXML.utf8)) == ["Атом-заголовок"], "atom title")

        // сравнение версий для проверки обновлений; dev-сборка несравнима
        precondition(isNewerVersion("1.0.5", than: "1.0.4"), "1.0.5 > 1.0.4")
        precondition(!isNewerVersion("1.0.4", than: "1.0.4"), "equal versions")
        precondition(isNewerVersion("1.1", than: "1.0.9"), "1.1 > 1.0.9")
        precondition(!isNewerVersion("1.0.9", than: "1.1"), "1.0.9 < 1.1")
        precondition(!isNewerVersion("1.0.5", than: "dev"), "dev incomparable")

        print("selftest ok: \(agent.animations.count) animations, "
              + "\(cropped) frames cropped, sheet \(sheet.width)x\(sheet.height), "
              + "\(tips.count) tips, \(soundKeys.count) sounds, "
              + "\(agentTipsChecked) agent tip files")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("selftest failed: \(error)\n".utf8))
        exit(1)
    }
}
