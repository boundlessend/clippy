import Foundation

// pure: интервал со случайным разбросом, не короче 1 с
func jitteredInterval(baseSeconds: Double, jitterSeconds: Double) -> Double {
    guard jitterSeconds > 0 else { return max(1, baseSeconds) }
    return max(1, baseSeconds + Double.random(in: -jitterSeconds...jitterSeconds))
}

// повторяющийся показ по интервалу. one-shot таймер перепланируется на каждом тике,
// чтобы разброс менялся раз за разом. показ пропускается, если экран неактивен.
@MainActor
final class Scheduler {
    private let firstDelaySeconds: Double
    private let baseInterval: () -> Double         // читается на каждом тике -> смена частоты на лету
    private let isAllowed: () -> Bool
    private let action: () -> Void
    private var timer: DispatchSourceTimer?

    init(firstDelaySeconds: Double, baseInterval: @escaping () -> Double,
         isAllowed: @escaping () -> Bool, action: @escaping () -> Void) {
        self.firstDelaySeconds = firstDelaySeconds
        self.baseInterval = baseInterval
        self.isAllowed = isAllowed
        self.action = action
    }

    func start() {
        scheduleNext(after: firstDelaySeconds)
    }

    private func scheduleNext(after delay: Double) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + delay)
        t.setEventHandler { [weak self] in self?.fire() }
        timer?.cancel()
        timer = t
        t.resume()
    }

    private func fire() {
        if isAllowed() { action() }
        let base = baseInterval()
        scheduleNext(after: jitteredInterval(baseSeconds: base,
                                             jitterSeconds: min(60, base * 0.1)))
    }
}
