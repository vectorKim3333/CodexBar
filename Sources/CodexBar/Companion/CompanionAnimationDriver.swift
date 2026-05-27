import AppKit
import CodexBarCore
import Foundation
import QuartzCore

/// Frame-index 기반 sprite cycling driver — RunCat 의 `FrameAnimationView` 와 동일한 방식.
///
/// 이전엔 연속 phase(0~1) 기반이었지만 hand-crafted 프레임 시퀀스로 전환하면서
/// frame index(0~N-1) 기반으로 단순화. stage 별 `frameInterval` 을 frameCount 로
/// 나눠 per-frame interval 계산. `.idle` 은 frame 0 에 고정 (cycling 없이 정지).
@MainActor
@Observable
final class CompanionAnimationDriver {
    private(set) var frameIndex: Int = 0
    var stage: CompanionPaceStage = .idle {
        didSet { self.applyStageChange() }
    }

    var onFrame: ((Int) -> Void)?

    private var frameCount: Int = 1
    private var timerTask: Task<Void, Never>?

    init() {}

    /// frameCount 를 알려준 뒤 cycling 시작. 캐릭터 변경 시 다시 호출.
    func configure(frameCount: Int) {
        self.frameCount = max(1, frameCount)
        if self.frameIndex >= self.frameCount {
            self.frameIndex = 0
        }
    }

    func start() {
        self.applyStageChange()
    }

    func stop() {
        self.timerTask?.cancel()
        self.timerTask = nil
    }

    private func applyStageChange() {
        self.timerTask?.cancel()
        let interval = self.perFrameInterval(for: self.stage)
        guard interval > 0, self.frameCount > 1 else {
            // .idle 등 정지 상태 — frame 0 고정.
            self.frameIndex = 0
            self.onFrame?(self.frameIndex)
            return
        }
        // 즉시 첫 tick 발화 후 주기 반복.
        self.onFrame?(self.frameIndex)
        self.timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                self.frameIndex = (self.frameIndex + 1) % self.frameCount
                self.onFrame?(self.frameIndex)
            }
        }
    }

    /// Stage 가 cycling 을 멈춰야 하는 경우(.idle) 0 반환 → driver 가 정지.
    private func perFrameInterval(for stage: CompanionPaceStage) -> TimeInterval {
        switch stage {
        case .idle: return 0
        case .slow, .normal, .fast, .burst:
            return stage.frameInterval / Double(self.frameCount)
        }
    }
}
