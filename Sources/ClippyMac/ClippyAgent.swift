import Foundation
import CoreGraphics
import ImageIO

// ресурс-бандл SwiftPM. Bundle.module ищет его по Bundle.main.bundleURL (у .app - корень .app)
// и падает fatalError, когда он лежит в стандартном Contents/Resources. резолвим сами:
// Contents/Resources у .app либо папка бинарника у dev-сборки (swift run). .module - последний фолбэк
let resourceBundle: Bundle = {
    let name = "ClippyMac_ClippyMac.bundle"
    let fm = FileManager.default
    let roots = [Bundle.main.resourceURL,
                 Bundle.main.executableURL?.deletingLastPathComponent(),
                 Bundle.main.bundleURL].compactMap { $0 }
    for root in roots {
        let url = root.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path), let b = Bundle(url: url) { return b }
    }
    return .module
}()

// модель ClippyJS agent.js (сконвертирован в clippy_agent.json).
// overlayCount=1, поэтому каждый кадр - максимум один слой [x,y] в спрайтшите.

struct ClippyAgent: Decodable {
    let framesize: [Int]                 // [width, height]
    let animations: [String: Animation]

    var frameSize: CGSize { CGSize(width: framesize[0], height: framesize[1]) }
}

struct Animation: Decodable {
    let frames: [Frame]
}

struct Frame: Decodable {
    let duration: Int                    // мс
    let images: [[Int]]?                 // слои [[x,y]]; nil = пустой кадр
    let exitBranch: Int?                 // только парсинг/валидация; в рантайме idle идёт линейно
    let branching: Branching?
    let sound: String?                   // ключ звука в sounds (1..15)
}

struct Branching: Decodable {
    let branches: [Branch]
}

struct Branch: Decodable {
    let frameIndex: Int
    let weight: Int
}

enum AssetError: Error { case missing(String) }

// directory == nil -> встроенный агент из бандла; иначе agent.json из папки персонажа
func loadClippyAgent(from directory: URL?) throws -> ClippyAgent {
    let url: URL
    if let directory {
        url = directory.appendingPathComponent("agent.json")
    } else if let bundled = resourceBundle.url(forResource: "clippy_agent", withExtension: "json") {
        url = bundled
    } else {
        throw AssetError.missing("clippy_agent.json")
    }
    let agent = try JSONDecoder().decode(ClippyAgent.self, from: Data(contentsOf: url))
    guard agent.framesize.count == 2 else {          // чужой agent.json может быть кривым
        throw AssetError.missing("framesize должен быть [w,h]")
    }
    return agent
}

// directory == nil -> встроенный спрайтшит из бандла; иначе map.png из папки персонажа
func loadSpriteSheet(from directory: URL?) throws -> CGImage {
    let url: URL
    if let directory {
        url = directory.appendingPathComponent("map.png")
    } else if let bundled = resourceBundle.url(forResource: "clippy_map", withExtension: "png") {
        url = bundled
    } else {
        throw AssetError.missing("clippy_map.png")
    }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw AssetError.missing(url.lastPathComponent)
    }
    return img
}

// pure: вырезать кадр из спрайтшита по координате левого верхнего угла
func cropFrame(sheet: CGImage, at point: [Int], frameSize: CGSize) -> CGImage? {
    guard point.count == 2 else { return nil }       // кривой слой [x,y] у чужого агента
    let rect = CGRect(x: point[0], y: point[1],
                      width: Int(frameSize.width), height: Int(frameSize.height))
    // rect чужого агента может выйти за спрайтшит: cropping тогда вернёт кадр меньшего
    // размера и исказит композицию - вместо этого согласованно пропускаем слой (nil)
    let bounds = CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)
    guard bounds.contains(rect) else { return nil }
    return sheet.cropping(to: rect)
}
