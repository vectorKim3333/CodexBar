// Tests/CodexBarTests/Companion/CompanionPaceStageTests.swift
import CodexBarCore
import Testing

struct CompanionPaceStageTests {
    @Test
    func `frameInterval is monotonically decreasing from idle to burst`() {
        let stages: [CompanionPaceStage] = [.idle, .slow, .normal, .fast, .burst]
        let intervals = stages.map(\.frameInterval)
        for pair in zip(intervals, intervals.dropFirst()) {
            #expect(pair.0 > pair.1)
        }
    }

    @Test
    func `idle frameInterval is at least 10 seconds (slow breathing)`() {
        #expect(CompanionPaceStage.idle.frameInterval >= 10)
    }

    @Test
    func `burst frameInterval is at most 200ms`() {
        #expect(CompanionPaceStage.burst.frameInterval <= 0.2)
    }

    @Test
    func `character maps to species and style consistently`() {
        #expect(CompanionCharacter.catPixel.species == .cat)
        #expect(CompanionCharacter.catPixel.style == .pixel)
        #expect(CompanionCharacter.dogLine.species == .dog)
        #expect(CompanionCharacter.dogLine.style == .line)
    }

    @Test
    func `CompanionCharacter has exactly 4 cases`() {
        #expect(CompanionCharacter.allCases.count == 4)
    }
}
