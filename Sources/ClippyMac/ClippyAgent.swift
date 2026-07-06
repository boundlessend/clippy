import Foundation
import CoreGraphics
import ImageIO

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
    let exitBranch: Int?
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
    } else if let bundled = Bundle.module.url(forResource: "clippy_agent", withExtension: "json") {
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
    } else if let bundled = Bundle.module.url(forResource: "clippy_map", withExtension: "png") {
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
    return sheet.cropping(to: rect)
}
