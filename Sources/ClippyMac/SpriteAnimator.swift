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
    private let soundsBase: URL?          // папка sounds персонажа; nil -> звуки из бандла
    private let onRender: (() -> Void)?   // вызывается после каждого кадра (обновить док-иконку)
    private let idleNames: [String]
    private var token = 0                 // растёт при смене анимации, гасит старую цепочку
    private var players: [String: AVAudioPlayer] = [:]

    init(imageView: NSImageView, sheet: CGImage, agent: ClippyAgent,
         soundsBase: URL?, onRender: (() -> Void)?) {
        self.imageView = imageView
        self.sheet = sheet
        self.agent = agent
        self.soundsBase = soundsBase
        self.onRender = onRender
        // только реально существующие idle-анимации; если их нет - любые (иначе пустой кадр)
        let idle = (agent.animations.keys.filter { $0.hasPrefix("Idle") } + ["RestPose"])
            .filter { agent.animations[$0] != nil }
        self.idleNames = idle.isEmpty ? Array(agent.animations.keys) : idle
    }

    // проиграть анимацию (maxSteps ограничивает зацикленные idle), затем completion
    func play(_ name: String, maxSteps: Int? = nil, then completion: (() -> Void)? = nil) {
        guard let anim = agent.animations[name] else { completion?(); return }
        token += 1
        step(anim.frames, index: 0, stepsLeft: maxSteps, myToken: token, completion: completion)
    }

    // живой idle: анимация «туда-сюда» (кадры вперёд, затем назад) - плавнее, без
    // рывка на стыке; через пару циклов берём другую idle. branching здесь не нужен
    func loopIdle() {
        let name = idleNames.randomElement() ?? "RestPose"
        guard let frames = agent.animations[name]?.frames, frames.count > 1 else {
            if let f = agent.animations[name]?.frames.first { render(f) }   // одиночный кадр
            token += 1
            let myToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, myToken == self.token else { return }
                self.loopIdle()
            }
            return
        }
        let fwd = Array(frames.indices)                          // 0..n-1
        let back = Array(fwd.dropFirst().dropLast().reversed())  // n-2..1 (крайние не дублируем)
        playSequence(frames, order: fwd + back, cycles: 2) { [weak self] in self?.loopIdle() }
    }

    // проиграть кадры в заданном порядке, повторить cycles раз, затем completion
    private func playSequence(_ frames: [Frame], order: [Int], cycles: Int,
                              then: @escaping () -> Void) {
        token += 1
        let myToken = token
        func run(_ pos: Int, _ cyclesLeft: Int) {
            guard myToken == token else { return }              // перебито новой анимацией
            if pos >= order.count {
                if cyclesLeft <= 1 { then(); return }
                run(0, cyclesLeft - 1); return
            }
            render(frames[order[pos]])                 // idle-петля без звука (иначе он зациклится)
            let delay = Double(max(frames[order[pos]].duration, 1)) / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { run(pos + 1, cyclesLeft) }
        }
        run(0, cycles)
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
        // кадр может состоять из нескольких оверлеев (overlayCount>1) - рисуем стопкой
        let layers = (frame.images ?? []).compactMap {
            cropFrame(sheet: sheet, at: $0, frameSize: agent.frameSize)
        }
        imageView.image = composite(layers)
        onRender?()
    }

    // сложить слои кадра в одну картинку (первый снизу); nil - пустой кадр
    private func composite(_ layers: [CGImage]) -> NSImage? {
        guard let first = layers.first else { return nil }
        if layers.count == 1 { return NSImage(cgImage: first, size: agent.frameSize) }
        let composed = NSImage(size: agent.frameSize)
        composed.lockFocus()
        let rect = NSRect(origin: .zero, size: agent.frameSize)
        for layer in layers { NSImage(cgImage: layer, size: agent.frameSize).draw(in: rect) }
        composed.unlockFocus()
        return composed
    }

    private func playSound(_ frame: Frame) {
        guard !AppSettings.shared.muted, let key = frame.sound,
              let player = soundPlayer(key) else { return }
        player.currentTime = 0
        player.play()
    }

    private func soundPlayer(_ key: String) -> AVAudioPlayer? {
        if let cached = players[key] { return cached }
        let url = soundsBase?.appendingPathComponent("\(key).mp3")
            ?? Bundle.module.url(forResource: key, withExtension: "mp3")
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[key] = player
        return player
    }
}
