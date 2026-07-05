import Foundation
import AppKit

// проверка логики без GUI: парсинг agent.json и кроп каждого кадра.
// запуск: CLIPPY_SELFTEST=1 swift run
@MainActor
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

        // планировщик: разброс не выходит за границы и не короче 1 с
        for _ in 0..<1000 {
            let v = jitteredInterval(baseSeconds: 600, jitterSeconds: 60)
            precondition(v >= 540 && v <= 660 && v >= 1, "jitter out of range: \(v)")
        }

        print("selftest ok: \(agent.animations.count) animations, "
              + "\(cropped) frames cropped, sheet \(sheet.width)x\(sheet.height), "
              + "\(tips.count) tips")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("selftest failed: \(error)\n".utf8))
        exit(1)
    }
}
