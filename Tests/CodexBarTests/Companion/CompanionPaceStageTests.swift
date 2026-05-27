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
        #expect(CompanionCharacter.dog.species == .dog)
        #expect(CompanionCharacter.cat.species == .cat)
        #expect(CompanionCharacter.figureRun.species == .human)
        #expect(CompanionCharacter.flame.species == .object)
        // 모든 캐릭터가 SF Symbol vector 라 style 은 .symbol 단일.
        for c in CompanionCharacter.allCases {
            #expect(c.style == .symbol)
        }
    }

    @Test
    func `CompanionCharacter has 8 cases`() {
        #expect(CompanionCharacter.allCases.count == 8)
        #expect(CompanionCharacter.allCases.contains(.dog))
        #expect(CompanionCharacter.allCases.contains(.cat))
    }
}
