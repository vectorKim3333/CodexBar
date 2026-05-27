import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct CompanionIconRendererTests {
    @Test
    func `produces template image for each character/stage`() {
        for character in CompanionCharacter.allCases {
            for stage in CompanionPaceStage.allCases {
                let image = CompanionIconRenderer.render(character: character, stage: stage, phase: 0.0)
                #expect(image.isTemplate)
                #expect(image.size.width > 0)
                #expect(image.size.height > 0)
            }
        }
    }

    @Test
    func `cache returns same instance for same (character, stage, quantized phase)`() {
        CompanionIconRenderer.clearCache()
        let a = CompanionIconRenderer.render(character: .catPixel, stage: .normal, phase: 0.10)
        let b = CompanionIconRenderer.render(character: .catPixel, stage: .normal, phase: 0.10)
        #expect(a === b)
    }
}
