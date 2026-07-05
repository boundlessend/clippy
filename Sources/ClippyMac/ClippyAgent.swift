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

func loadClippyAgent() throws -> ClippyAgent {
    guard let url = Bundle.module.url(forResource: "clippy_agent", withExtension: "json") else {
        throw AssetError.missing("clippy_agent.json")
    }
    return try JSONDecoder().decode(ClippyAgent.self, from: Data(contentsOf: url))
}

func loadSpriteSheet() throws -> CGImage {
    guard let url = Bundle.module.url(forResource: "clippy_map", withExtension: "png"),
          let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw AssetError.missing("clippy_map.png")
    }
    return img
}

// pure: вырезать кадр из спрайтшита по координате левого верхнего угла
func cropFrame(sheet: CGImage, at point: [Int], frameSize: CGSize) -> CGImage? {
    let rect = CGRect(x: point[0], y: point[1],
                      width: Int(frameSize.width), height: Int(frameSize.height))
    return sheet.cropping(to: rect)
}
