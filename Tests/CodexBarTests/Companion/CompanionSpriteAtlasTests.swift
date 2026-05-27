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

    @Test
    func `catPixel has all required parts`() {
        let parts = CompanionSpriteAtlas.parts(for: .catPixel)
        let kinds = Set(parts.map { String(describing: $0.kind) })
        #expect(kinds.contains("body"))
        #expect(kinds.contains("tail"))
        // Two ears
        let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
        #expect(ears.count == 2)
        // Four legs
        let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
        #expect(legs.count == 4)
    }

    @Test
    func `catPixel part transforms produce finite values`() {
        let parts = CompanionSpriteAtlas.parts(for: .catPixel)
        for part in parts {
            for phase in stride(from: 0.0, through: 1.0, by: 0.1) {
                let t = part.animation.transform(phase)
                #expect(t.a.isFinite && t.b.isFinite && t.c.isFinite && t.d.isFinite && t.tx.isFinite && t.ty.isFinite)
            }
        }
    }

    @Test
    func `catLine has all required parts`() {
        let parts = CompanionSpriteAtlas.parts(for: .catLine)
        let kinds = Set(parts.map { String(describing: $0.kind) })
        #expect(kinds.contains("body"))
        #expect(kinds.contains("tail"))
        let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
        #expect(ears.count == 2)
        let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
        #expect(legs.count == 4)
        let whiskers = parts.filter {
            if case .whisker = $0.kind { return true } else { return false }
        }
        #expect(whiskers.count == 2)
    }

    @Test
    func `dogPixel has all required parts`() {
        let parts = CompanionSpriteAtlas.parts(for: .dogPixel)
        let ears = parts.filter { if case .ear = $0.kind { return true } else { return false } }
        let legs = parts.filter { if case .leg = $0.kind { return true } else { return false } }
        #expect(ears.count == 2)
        #expect(legs.count == 4)
        #expect(parts.contains { if case .tail = $0.kind { return true } else { return false } })
    }
}
