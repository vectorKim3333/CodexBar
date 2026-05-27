// Sources/CodexBar/Companion/CompanionPreviewView.swift
import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct CompanionPreviewView: View {
    let character: CompanionCharacter

    private let stages: [CompanionPaceStage] = [.idle, .slow, .normal, .fast, .burst]
    /// 한 stage 당 미리보기 노출 시간 (3초). 5개 stage → 15초 사이클.
    private let stageHoldDuration: TimeInterval = 3.0
    /// TimelineView 의 minimum tick 주기. burst frameInterval / frameCount 보다 짧게.
    private let tickInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        let frameCount = CompanionSpriteFrameRenderer.frameCount(for: self.character)
        TimelineView(.animation(minimumInterval: self.tickInterval)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cycleDuration = self.stageHoldDuration * Double(self.stages.count)
            let cyclePos = elapsed.truncatingRemainder(dividingBy: cycleDuration)
            let stageIdx = Int(cyclePos / self.stageHoldDuration) % self.stages.count
            let stage = self.stages[stageIdx]
            let frameIndex = self.currentFrameIndex(
                stage: stage,
                elapsed: elapsed,
                frameCount: frameCount)
            let image = CompanionSpriteFrameRenderer.render(
                character: self.character,
                frameIndex: frameIndex,
                size: NSSize(width: 88, height: 72))
            HStack(spacing: 16) {
                Image(nsImage: image)
                VStack(alignment: .leading) {
                    Text(L("companion.preview.label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(self.stageLabel(stage))
                        .font(.body.monospaced())
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
    }

    private func currentFrameIndex(stage: CompanionPaceStage, elapsed: TimeInterval, frameCount: Int) -> Int {
        // .idle 은 frame 0 고정.
        guard stage != .idle, frameCount > 1 else { return 0 }
        let perFrame = stage.frameInterval / Double(frameCount)
        guard perFrame > 0 else { return 0 }
        return Int(elapsed / perFrame) % frameCount
    }

    private func stageLabel(_ s: CompanionPaceStage) -> String {
        switch s {
        case .idle:   return L("companion.stage.idle")
        case .slow:   return L("companion.stage.slow")
        case .normal: return L("companion.stage.normal")
        case .fast:   return L("companion.stage.fast")
        case .burst:  return L("companion.stage.burst")
        }
    }
}
