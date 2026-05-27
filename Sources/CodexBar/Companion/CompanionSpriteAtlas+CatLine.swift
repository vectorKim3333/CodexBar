// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatLine.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catLineParts: [CompanionPart] = _buildCatLineParts()
}

// swiftlint:disable function_body_length
private func _buildCatLineParts() -> [CompanionPart] {
    // 22×16 line-art cat, profile facing left.
    //  - 2 sharp triangular ears (one quadCurve each, apex above head)
    //  - Smooth rounded head with visible eye + nose dot
    //  - 2 whiskers radiating from cheek
    //  - Slim curved torso, elegant curled-up tail at the back
    //  - 4 vertical legs

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2.0 * Double.pi))
    }

    // Pendulum leg swing, ±15° from upright.
    func legSwing(offset: Double, originX: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 15.0 * Double.pi / 180.0
            return CGAffineTransform.identity
                .translatedBy(x: originX, y: 11)
                .rotated(by: angle)
                .translatedBy(x: -originX, y: -11)
        }
    }

    // Cat tail: slow elegant wag ±15° around the tail base near (18, 8).
    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let angle = sin(phase * 2.0 * Double.pi) * 15.0 * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 18, y: 8)
            .rotated(by: angle)
            .translatedBy(x: -18, y: -8)
    }

    // Whisker twitch: ±5°, pivoting around the cheek root (3, 8.5).
    func whiskerTwitch(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = sin(local * 2.0 * Double.pi) * 5.0 * Double.pi / 180.0
            return CGAffineTransform.identity
                .translatedBy(x: 3, y: 8.5)
                .rotated(by: angle)
                .translatedBy(x: -3, y: -8.5)
        }
    }

    let earStill: @Sendable (Double) -> CGAffineTransform = { _ in .identity }

    // Ears: each a single quadCurve forming a triangular arc.
    //  Left:  base (2,4) → apex (3,1) → base (4,4)
    //  Right: base (6,4) → apex (7,1) → base (8,4)
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .quadCurve(x1: 2, y1: 4, cx: 3, cy: 1, x2: 4, y2: 4),
        animation: CompanionPartAnimation(transform: earStill))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .quadCurve(x1: 6, y1: 4, cx: 7, cy: 1, x2: 8, y2: 4),
        animation: CompanionPartAnimation(transform: earStill))

    // Head: forehead/back-of-head curve from left ear base across to right ear base.
    let headTop = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 4, y1: 4, cx: 5, cy: 3, x2: 6, y2: 4),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Cheek/chin: down the left side, around the muzzle and back up to body.
    let headLeft = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 2, y1: 4, cx: 1, cy: 8, x2: 4, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))
    let headBottom = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 4, y1: 10, cx: 8, cy: 10, x2: 9, y2: 7),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Back of head connecting to body.
    let headRight = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 8, y1: 4, cx: 9, cy: 5, x2: 9, y2: 7),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Facial features
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 4.5, cy: 6.5, radius: 0.6),
        animation: CompanionPartAnimation(transform: bodyBob))
    let nose = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 2.5, cy: 8.0, radius: 0.4),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Whiskers: 2 short angled lines from cheek root outward to the left.
    let whiskerLeft = CompanionPart(
        kind: .whisker(side: .left),
        drawCommand: .line(x1: 3, y1: 8, x2: 0, y2: 7),
        animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0)))
    let whiskerRight = CompanionPart(
        kind: .whisker(side: .right),
        drawCommand: .line(x1: 3, y1: 9, x2: 0, y2: 10),
        animation: CompanionPartAnimation(transform: whiskerTwitch(offset: 0.5)))

    // Body: top arc from neck to hindquarters, bottom flat-ish belly line.
    let bodyTop = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 9, y1: 7, cx: 14, cy: 6, x2: 18, y2: 8),
        animation: CompanionPartAnimation(transform: bodyBob))
    let bodyBottom = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 9, y1: 10, x2: 17, y2: 11),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Tail: curls up and slightly back over the body.
    let tail = CompanionPart(
        kind: .tail,
        drawCommand: .quadCurve(x1: 18, y1: 8, cx: 21, cy: 4, x2: 19, y2: 2),
        animation: CompanionPartAnimation(transform: tailWag))

    // 4 legs, vertical lines under the torso.
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .line(x1: 10, y1: 11, x2: 10, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0, originX: 10)))
    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .line(x1: 12, y1: 11, x2: 12, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.25, originX: 12)))
    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .line(x1: 15, y1: 11, x2: 15, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.5, originX: 15)))
    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .line(x1: 17, y1: 11, x2: 17, y2: 14),
        animation: CompanionPartAnimation(transform: legSwing(offset: 0.75, originX: 17)))

    return [
        earLeft, earRight,
        headTop, headLeft, headBottom, headRight,
        eye, nose,
        whiskerLeft, whiskerRight,
        bodyTop, bodyBottom,
        tail,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
