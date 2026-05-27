import AppKit
import CodexBarCore
import Foundation
import QuartzCore

@MainActor
@Observable
final class CompanionAnimationDriver {
    private(set) var phase: Double = 0
    var stage: CompanionPaceStage = .idle

    var onFrame: ((Double) -> Void)?

    private var displayLink: DisplayLinkDriver?
    private var lastTickTime: CFTimeInterval = 0

    init() {}

    func start() {
        guard self.displayLink == nil else { return }
        let link = DisplayLinkDriver { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = self.lastTickTime == 0 ? 0 : now - self.lastTickTime
            self.lastTickTime = now
            if dt > 0 {
                self.advancePhase(deltaTime: dt)
                self.onFrame?(self.phase)
            }
        }
        // Cap at 30 FPS — sufficient for our stages.
        link.start(fps: 30)
        self.displayLink = link
    }

    func stop() {
        self.displayLink?.stop()
        self.displayLink = nil
        self.lastTickTime = 0
    }

    /// Test-only and tick-internal. Advances phase by dt seconds at current stage.
    func advancePhase(deltaTime: TimeInterval) {
        let interval = self.stage.frameInterval
        guard interval > 0 else { return }
        let delta = deltaTime / interval
        self.phase = (self.phase + delta).truncatingRemainder(dividingBy: 1.0)
        if self.phase < 0 { self.phase += 1 }
    }
}
