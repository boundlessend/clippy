import Foundation
import AppKit

// проверка логики без GUI: парсинг agent.json и кроп каждого кадра.
// запуск: CLIPPY_SELFTEST=1 swift run
func runSelfCheckIfRequested() {
    guard ProcessInfo.processInfo.environment["CLIPPY_SELFTEST"] != nil else { return }
    do {
        let agent = try loadClippyAgent()
        precondition(agent.framesize.count == 2, "framesize must be [w,h]")
        let fs = agent.frameSize
        precondition(fs.width > 0 && fs.height > 0, "empty frame size")

        let sheet = try loadSpriteSheet()
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
        guard let turl = Bundle.module.url(forResource: "tips", withExtension: "json") else {
            fatalError("tips.json missing")
        }
        let tips = try JSONDecoder().decode([String].self, from: Data(contentsOf: turl))
        precondition(!tips.isEmpty && tips.allSatisfy { !$0.isEmpty }, "tips must be non-empty")
        _ = try LocalJSONProvider()

        // иконка меню-бара присутствует и грузится
        guard let micon = Bundle.module.url(forResource: "menubar", withExtension: "png"),
              NSImage(contentsOf: micon) != nil else {
            fatalError("menubar.png missing or unreadable")
        }

        // планировщик: разброс не выходит за границы и не короче 1 с
        for _ in 0..<1000 {
            let v = jitteredInterval(baseSeconds: 600, jitterSeconds: 60)
            precondition(v >= 540 && v <= 660 && v >= 1, "jitter out of range: \(v)")
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
                Bundle.module.url(forResource: key, withExtension: "mp3") != nil,
                "missing sound \(key).mp3")
        }

        print("selftest ok: \(agent.animations.count) animations, "
              + "\(cropped) frames cropped, sheet \(sheet.width)x\(sheet.height), "
              + "\(tips.count) tips, \(soundKeys.count) sounds")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("selftest failed: \(error)\n".utf8))
        exit(1)
    }
}
