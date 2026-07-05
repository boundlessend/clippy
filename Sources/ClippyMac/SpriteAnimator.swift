import AppKit
import AVFoundation

// pure: выбрать следующий кадр с учётом branching (вероятностный прыжок по weight)
func nextFrameIndex(current: Int, frames: [Frame]) -> Int {
    if let b = frames[current].branching {
        var r = Int.random(in: 0..<100)
        for branch in b.branches {
            if r < branch.weight { return branch.frameIndex }
            r -= branch.weight
        }
    }
    return current + 1
}

// проигрыватель кадров: рисует кадр, играет его звук, ветвится по branching.
@MainActor
final class SpriteAnimator {
    private let imageView: NSImageView
    private let sheet: CGImage
    private let agent: ClippyAgent
    private let idleNames: [String]
    private var token = 0                 // растёт при смене анимации, гасит старую цепочку
    private var players: [String: AVAudioPlayer] = [:]

    init(imageView: NSImageView, sheet: CGImage, agent: ClippyAgent) {
        self.imageView = imageView
        self.sheet = sheet
        self.agent = agent
        self.idleNames = agent.animations.keys.filter { $0.hasPrefix("Idle") } + ["RestPose"]
    }

    // проиграть анимацию (maxSteps ограничивает зацикленные idle), затем completion
    func play(_ name: String, maxSteps: Int? = nil, then completion: (() -> Void)? = nil) {
        guard let anim = agent.animations[name] else { completion?(); return }
        token += 1
        step(anim.frames, index: 0, stepsLeft: maxSteps, myToken: token, completion: completion)
    }

    // живой idle: случайный жест из Idle*/RestPose, потом следующий
    func loopIdle() {
        let name = idleNames.randomElement() ?? "RestPose"
        play(name, maxSteps: 50) { [weak self] in self?.loopIdle() }
    }

    private func step(_ frames: [Frame], index: Int, stepsLeft: Int?, myToken: Int,
                      completion: (() -> Void)?) {
        guard myToken == token else { return }                 // перебито новой анимацией
        guard index >= 0, index < frames.count, (stepsLeft ?? 1) > 0 else {
            completion?(); return
        }
        let frame = frames[index]
        render(frame)
        playSound(frame)
        let delay = Double(max(frame.duration, 1)) / 1000.0
        let next = nextFrameIndex(current: index, frames: frames)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.step(frames, index: next, stepsLeft: stepsLeft.map { $0 - 1 },
                       myToken: myToken, completion: completion)
        }
    }

    private func render(_ frame: Frame) {
        guard let point = frame.images?.first,
              let cg = cropFrame(sheet: sheet, at: point, frameSize: agent.frameSize) else {
            imageView.image = nil                              // пустой кадр
            return
        }
        imageView.image = NSImage(cgImage: cg, size: agent.frameSize)
    }

    private func playSound(_ frame: Frame) {
        guard !AppSettings.shared.muted, let key = frame.sound,
              let player = soundPlayer(key) else { return }
        player.currentTime = 0
        player.play()
    }

    private func soundPlayer(_ key: String) -> AVAudioPlayer? {
        if let cached = players[key] { return cached }
        guard let url = Bundle.module.url(forResource: key, withExtension: "mp3"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[key] = player
        return player
    }
}
