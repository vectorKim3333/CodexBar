// Sources/CodexBar/Companion/CompanionSpriteAtlas+DogLine.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogLineParts: [CompanionPart] = _buildDogLineParts()
}

// swiftlint:disable function_body_length
private func _buildDogLineParts() -> [CompanionPart] {
    // 22×16 line-art dog, profile facing left.
    //  - Snout sticks out left of the head with a visible nose dot
    //  - Floppy ears DROOP DOWN below the head crown
    //  - Visible eye on the head
    //  - Stockier body, short upright tail at the back

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: -0.5 * sin(phase * 2.0 * Double.pi))
    }

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

    // Dog tail wag — faster than cat, ±20° at 2× frequency.
    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let angle = sin(phase * 4.0 * Double.pi) * 20.0 * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 18, y: 8)
            .rotated(by: angle)
            .translatedBy(x: -18, y: -8)
    }

    // Floppy ears just stay still — animation kept making them swing weirdly.
    let earStill: @Sendable (Double) -> CGAffineTransform = { _ in .identity }

    // Snout — two short lines forming a wedge sticking left from the face.
    let snoutTop = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 7),
        animation: CompanionPartAnimation(transform: bodyBob))
    let snoutBottom = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 0, y1: 8, x2: 3, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Nose at the tip of the snout.
    let nose = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 0.5, cy: 8.0, radius: 0.6),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Head crown — rounded top from snout root up and back.
    let headTop = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 3, y1: 7, cx: 5, cy: 3, x2: 8, y2: 5),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Cheek/jaw curve from snout bottom under the face.
    let headBottom = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 3, y1: 10, cx: 5, cy: 11, x2: 8, y2: 10),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Eye
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .dot(cx: 5.0, cy: 7.0, radius: 0.6),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Body top/bottom curves connecting head to hindquarters.
    let bodyTop = CompanionPart(
        kind: .body,
        drawCommand: .quadCurve(x1: 8, y1: 5, cx: 13, cy: 6, x2: 18, y2: 8),
        animation: CompanionPartAnimation(transform: bodyBob))
    let bodyBottom = CompanionPart(
        kind: .body,
        drawCommand: .line(x1: 8, y1: 10, x2: 17, y2: 11),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Floppy ears — single quad curve each, drooping DOWN from the crown
    // past the cheek line. Distinctly dog-like.
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .quadCurve(x1: 5, y1: 4, cx: 3, cy: 8, x2: 5, y2: 10),
        animation: CompanionPartAnimation(transform: earStill))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .quadCurve(x1: 8, y1: 5, cx: 8, cy: 9, x2: 6, y2: 10),
        animation: CompanionPartAnimation(transform: earStill))

    // Short upright tail at the rear.
    let tail = CompanionPart(
        kind: .tail,
        drawCommand: .line(x1: 18, y1: 8, x2: 20, y2: 4),
        animation: CompanionPartAnimation(transform: tailWag))

    // 4 legs.
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
        snoutTop, snoutBottom, nose,
        headTop, headBottom, eye,
        bodyTop, bodyBottom,
        earLeft, earRight,
        tail,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
