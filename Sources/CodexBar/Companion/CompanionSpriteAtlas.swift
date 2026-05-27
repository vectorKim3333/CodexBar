import CodexBarCore
import CoreGraphics
import Foundation

enum CompanionPartKind: Sendable, Hashable {
    case body
    case leg(index: Int)   // 1...4
    case tail
    case ear(side: Side)
    case whisker(side: Side)

    enum Side: Sendable, Hashable { case left, right }
}

/// Coordinate space: integer grid 0..<width × 0..<height (defined per character).
/// Renderer scales to NSImage size.
enum CompanionDrawCommand: Sendable {
    /// Filled rect at integer pixel coordinates.
    case pixelRect(x: Int, y: Int, width: Int, height: Int)
    /// Stroked line between two integer points.
    case line(x1: Int, y1: Int, x2: Int, y2: Int)
    /// Stroked quadratic Bézier curve.
    case quadCurve(x1: Int, y1: Int, cx: Int, cy: Int, x2: Int, y2: Int)
    /// Filled ellipse (used for eyes/dots).
    case dot(cx: Double, cy: Double, radius: Double)
}

/// How a part animates with the master phase (0...1).
struct CompanionPartAnimation: Sendable {
    /// Phase offset applied to this part (0...1).
    let phaseOffset: Double
    /// Transform to apply at given phase.
    let transform: @Sendable (Double) -> CGAffineTransform

    init(phaseOffset: Double = 0,
         transform: @escaping @Sendable (Double) -> CGAffineTransform = { _ in .identity })
    {
        self.phaseOffset = phaseOffset
        self.transform = transform
    }

    static let none = CompanionPartAnimation()
}

struct CompanionPart: Sendable {
    let kind: CompanionPartKind
    let drawCommand: CompanionDrawCommand
    let animation: CompanionPartAnimation
}

/// Atlas: looks up parts for a character. Filled by character-specific files.
enum CompanionSpriteAtlas {
    /// Coordinate grid size for the character.
    static func gridSize(for character: CompanionCharacter) -> CGSize {
        switch character.style {
        case .pixel: return CGSize(width: 20, height: 16)
        case .line:  return CGSize(width: 22, height: 16)
        }
    }

    static func parts(for character: CompanionCharacter) -> [CompanionPart] {
        switch character {
        case .catPixel: return Self.catPixelParts
        case .catLine:  return Self.catLineParts
        case .dogPixel: return Self.dogPixelParts
        case .dogLine:  return Self.dogLineParts
        }
    }

    // Stubs — populated in subsequent tasks
    static let catPixelParts: [CompanionPart] = _catPixelParts
    static let catLineParts: [CompanionPart] = _catLineParts
    static let dogPixelParts: [CompanionPart] = _dogPixelParts
    static let dogLineParts: [CompanionPart] = []
}
