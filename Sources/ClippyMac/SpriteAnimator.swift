import AppKit

// проигрыватель кадров: держит спрайтшит и рисует текущий кадр в NSImageView.
// P1: линейное проигрывание, branching игнорируется (см. PLAN.md).
@MainActor
final class SpriteAnimator {
    private let imageView: NSImageView
    private let sheet: CGImage
    private let agent: ClippyAgent
    private var token = 0                 // растёт при смене анимации, гасит старую цепочку

    init(imageView: NSImageView, sheet: CGImage, agent: ClippyAgent) {
        self.imageView = imageView
        self.sheet = sheet
        self.agent = agent
    }

    // проиграть анимацию один раз, затем вызвать completion
    func play(_ name: String, then completion: (() -> Void)? = nil) {
        guard let anim = agent.animations[name] else { completion?(); return }
        token += 1
        runFrames(anim.frames, index: 0, myToken: token, completion: completion)
    }

    // зациклить анимацию (для idle)
    func loop(_ name: String) {
        play(name) { [weak self] in self?.loop(name) }
    }

    private func runFrames(_ frames: [Frame], index: Int, myToken: Int,
                           completion: (() -> Void)?) {
        guard myToken == token else { return }            // перебито новой анимацией
        guard index < frames.count else { completion?(); return }
        let frame = frames[index]
        render(frame)
        let delay = Double(max(frame.duration, 1)) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runFrames(frames, index: index + 1, myToken: myToken, completion: completion)
        }
    }

    private func render(_ frame: Frame) {
        guard let point = frame.images?.first,
              let cg = cropFrame(sheet: sheet, at: point, frameSize: agent.frameSize) else {
            imageView.image = nil                          // пустой кадр
            return
        }
        imageView.image = NSImage(cgImage: cg, size: agent.frameSize)
    }
}
