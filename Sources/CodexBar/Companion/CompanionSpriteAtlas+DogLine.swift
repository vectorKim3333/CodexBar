import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogLineParts: [CompanionPart] = _buildDogLineParts()
}

// swiftlint:disable function_body_length
private func _buildDogLineParts() -> [CompanionPart] {
    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2.0 * Double.pi))
    }

    func legSwing(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 20.0 * Double.pi / 180.0
            return CGAffineTransform.identity
                .translatedBy(x: originX, y: 12)
                .rotated(by: angle)
                .translatedBy(x: -originX, y: -12)
        }
    }

    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let angle = sin(phase * 4.0 * Double.pi) * 45.0 * Double.pi / 180.0   // fast wag, ±45°
        return CGAffineTransform.identity
            .translatedBy(x: 18, y: 8)
            .rotated(by: angle)
            .translatedBy(x: -18, y: -8)
    }

    func earSway(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 12.0 * Double.pi / 180.0
            return CGAffineTransform.identity
                .translatedBy(x: originX, y: 6)
                .rotated(by: angle)
                .translatedBy(x: -originX, y: -6)
        }
    }

    // Snout
    let snout1 = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 7),
        animation: CompanionPartAnimation(transform: bodyBob))
    let snout2 = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 9),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Head outline
    let head1 = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 3, y1: 6, cx: 4, cy: 10, x2: 7, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))
    let head2 = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 7, y1: 10, cx: 8, cy: 8, x2: 8, y2: 5),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Eye
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 5, cy: 7, radius: 0.6),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Body curve
    let bodyCurve = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 8, y1: 10, cx: 13, cy: 9, x2: 18, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Droopy ears
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .quadCurve(x1: 4, y1: 6, cx: 3, cy: 8, x2: 4, y2: 9),
        animation: CompanionPartAnimation(transform: earSway(offset: 0, originX: 4)))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .quadCurve(x1: 7, y1: 6, cx: 8, cy: 8, x2: 7, y2: 9),
        animation: CompanionPartAnimation(transform: earSway(offset: 0.5, originX: 7)))

    // Tail (upright, 2 line segments)
    let tail1 = CompanionPart(
        kind: .tail,
        drawCommand: .line(x1: 18, y1: 9, x2: 19, y2: 5),
        animation: CompanionPartAnimation(transform: tailWag))
    let tail2 = CompanionPart(
        kind: .tail,
        drawCommand: .line(x1: 19, y1: 5, x2: 20, y2: 4),
        animation: CompanionPartAnimation(transform: tailWag))

    // Legs
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .line(x1: 8, y1: 11, x2: 8, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0, originX: 8)))
    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .line(x1: 11, y1: 11, x2: 11, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.25, originX: 11)))
    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .line(x1: 14, y1: 11, x2: 14, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.5, originX: 14)))
    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .line(x1: 17, y1: 11, x2: 17, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.75, originX: 17)))

    return [
        snout1, snout2,
        head1, head2, eye, bodyCurve,
        earLeft, earRight,
        tail1, tail2,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
