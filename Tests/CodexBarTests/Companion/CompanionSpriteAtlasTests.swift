import Testing
@testable import CodexBar

@MainActor
struct CompanionSpriteAtlasTests {
    @Test
    func `data types compile`() {
        _ = CompanionPart(
            kind: .body,
            drawCommand: .pixelRect(x: 0, y: 0, width: 1, height: 1),
            animation: .none)
    }
}
