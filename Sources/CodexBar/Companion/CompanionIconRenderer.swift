import AppKit
import CodexBarCore
import CoreGraphics
import Foundation

@MainActor
enum CompanionIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()
    private static let phaseQuantizationSteps = 16   // 1.0 / 16 = 0.0625
    private static let defaultSize = NSSize(width: 18, height: 16)

    static func render(
        character: CompanionCharacter,
        stage: CompanionPaceStage,
        phase: Double,
        size: NSSize = defaultSize
    ) -> NSImage {
        let quantized = Int((phase.truncatingRemainder(dividingBy: 1.0))
            * Double(self.phaseQuantizationSteps)) % self.phaseQuantizationSteps
        let key = "\(character.rawValue)|\(stage.rawValue)|\(quantized)|\(Int(size.width))x\(Int(size.height))" as NSString

        if let cached = self.cache.object(forKey: key) { return cached }

        let image = self.drawImage(
            character: character,
            phase: Double(quantized) / Double(self.phaseQuantizationSteps),
            size: size)
        image.isTemplate = true
        self.cache.setObject(image, forKey: key)
        return image
    }

    static func clearCache() {
        self.cache.removeAllObjects()
    }

    private static func drawImage(character: CompanionCharacter, phase: Double, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let grid = CompanionSpriteAtlas.gridSize(for: character)
        let sx = size.width / grid.width
        let sy = size.height / grid.height
        ctx.scaleBy(x: sx, y: sy)
        // Convert from CG bottom-left origin to UI top-left origin so sprite atlases
        // (which use Y-down convention) render right-side up.
        ctx.translateBy(x: 0, y: grid.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(character.style == .line ? 1.2 / max(sx, sy) : 0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let parts = CompanionSpriteAtlas.parts(for: character)
        for part in parts {
            ctx.saveGState()
            let t = part.animation.transform(phase)
            ctx.concatenate(t)
            self.draw(part.drawCommand, in: ctx, style: character.style)
            ctx.restoreGState()
        }
        return image
    }

    private static func draw(_ command: CompanionDrawCommand, in ctx: CGContext, style: CompanionStyle) {
        switch command {
        case .pixelRect(let x, let y, let w, let h):
            let rect = CGRect(x: x, y: y, width: w, height: h)
            ctx.fill(rect)

        case .line(let x1, let y1, let x2, let y2):
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()

        case .quadCurve(let x1, let y1, let cx, let cy, let x2, let y2):
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addQuadCurve(
                to: CGPoint(x: x2, y: y2),
                control: CGPoint(x: cx, y: cy))
            ctx.strokePath()

        case .dot(let cx, let cy, let radius):
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            ctx.fillEllipse(in: rect)
        }
    }
}
