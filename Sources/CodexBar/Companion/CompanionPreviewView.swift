// Sources/CodexBar/Companion/CompanionPreviewView.swift
import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct CompanionPreviewView: View {
    let character: CompanionCharacter
    @State private var phase: Double = 0
    @State private var stageIndex: Int = 0

    private let stages: [CompanionPaceStage] = [.idle, .slow, .normal, .fast, .burst]
    private let cycleDuration: TimeInterval = 5.0   // 1s per stage
    private let frameInterval: TimeInterval = 1.0 / 30.0   // 30 FPS

    var body: some View {
        TimelineView(.animation(minimumInterval: self.frameInterval)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cyclePos = elapsed.truncatingRemainder(dividingBy: self.cycleDuration) / self.cycleDuration
            let stageIdx = Int(cyclePos * Double(self.stages.count)) % self.stages.count
            let stage = self.stages[stageIdx]
            let stagePhase = (elapsed / stage.frameInterval).truncatingRemainder(dividingBy: 1.0)
            let image = CompanionIconRenderer.render(
                character: self.character, stage: stage, phase: stagePhase,
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
