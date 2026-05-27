// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatLine.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catLineParts: [CompanionPart] = _buildCatLineParts()
}

// swiftlint:disable function_body_length
private func _buildCatLineParts() -> [CompanionPart] {
    // 22×16. Line drawings (path + curve). Legs as lines that pendulum-rotate.

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2.0 * Double.pi))
    }

    func legSwing(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 25.0 * Double.pi / 180.0   // ±25°
            return CGAffineTransform.identity
                .translatedBy(x: originX, y: 12)
                .rotated(by: angle)
                .translatedBy(x: -originX, y: -12)
        }
    }

    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let sinVal = sin(phase * 2.0 * Double.pi)
        let normalised = sinVal * 0.5 + 0.5
        let degrees = -20.0 + 55.0 * normalised  // -20°...+35°
        let angle = degrees * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 18, y: 10)
            .rotated(by: angle)
            .translatedBy(x: -18, y: -10)
    }

    func whiskerTwitch(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 10.0 * Double.pi / 180.0
            return CGAffineTransform.identity
                .translatedBy(x: 5, y: 9.5)
                .rotated(by: angle)
                .translatedBy(x: -5, y: -9.5)
        }
    }

    // Ears (2 quadCurves — one per side)
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .quadCurve(x1: 3, y1: 6, cx: 4, cy: 3, x2: 6, y2: 5),
        animation: CompanionPartAnimation())
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .quadCurve(x1: 9, y1: 5, cx: 9, cy: 3, x2: 11, y2: 6),
        animation: CompanionPartAnimation())

    // Head outline (quadCurves)
    let head1 = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 3, y1: 6, cx: 3, cy: 9, x2: 5, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))
    let head2 = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 5, y1: 10, cx: 11, cy: 9, x2: 11, y2: 6),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Eye
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 7, cy: 7, radius: 0.6),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Torso curve
    let torso = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 11, y1: 10, cx: 15, cy: 9, x2: 18, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Whiskers
    let whiskerLeft = CompanionPart(
        kind: .whisker(side: .left),
        drawCommand: .line(x1: 5, y1: 9, x2: 2, y2: 8),
        animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0)))
    let whiskerRight = CompanionPart(
        kind: .whisker(side: .right),
        drawCommand: .line(x1: 5, y1: 10, x2: 2, y2: 11),
        animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0.5)))

    // Tail (curve)
    let tail = CompanionPart(
        kind: .tail,
        drawCommand: .quadCurve(x1: 18, y1: 10, cx: 21, cy: 8, x2: 20, y2: 5),
        animation: CompanionPartAnimation(transform: tailWag))

    // Legs (lines that pendulum-rotate)
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .line(x1: 7, y1: 11, x2: 7, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0, originX: 7)))
    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .line(x1: 10, y1: 11, x2: 10, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.25, originX: 10)))
    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .line(x1: 13, y1: 11, x2: 13, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.5, originX: 13)))
    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .line(x1: 16, y1: 11, x2: 16, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.75, originX: 16)))

    return [
        earLeft, earRight,
        head1, head2, eye, torso,
        whiskerLeft, whiskerRight,
        tail,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
