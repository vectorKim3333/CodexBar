// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catPixelParts: [CompanionPart] = _buildCatPixelParts()
}

// swiftlint:disable function_body_length
private func _buildCatPixelParts() -> [CompanionPart] {
    // 20×16 pixel cat, profile facing left. Distinguishing features:
    //  - 2 sharp triangular pixel ears on top of head
    //  - Slim head distinct from a longer torso
    //  - Long tail that curls up at the back
    //  - 4 slim legs

    // Subtle 1px body bob.
    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
    }

    // Cat tail: slow elegant wag, narrow range (±15°), pivot at base of tail.
    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let angle = sin(phase * 2.0 * Double.pi) * 15.0 * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 16, y: 8)
            .rotated(by: angle)
            .translatedBy(x: -16, y: -8)
    }

    // 1px hop, half cycle up.
    func legLift(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -1)
        }
    }

    // Ears stay mostly still in template mode (animation looked twitchy).
    let earStill: @Sendable (Double) -> CGAffineTransform = { _ in .identity }

    // Head block — slim, square-ish (cats have smaller heads relative to torso).
    let head = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 2, y: 5, width: 6, height: 4),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Eye dot (single pixel)
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 4, y: 6, width: 1, height: 1),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Torso — extends right from head, slightly thicker than head row but lower.
    let torso = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 8, y: 7, width: 8, height: 4),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Pointed ears: 2-wide pixel triangles on top of head.
    // Left ear sits at x 2-3, right ear at x 6-7. Apex single pixel above 2px base.
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .pixelRect(x: 2, y: 3, width: 2, height: 2),
        animation: CompanionPartAnimation(transform: earStill))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .pixelRect(x: 6, y: 3, width: 2, height: 2),
        animation: CompanionPartAnimation(transform: earStill))

    // Tail (two segments): goes up and curls.
    let tail1 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 16, y: 7, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: tailWag))
    let tail2 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 17, y: 5, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: tailWag))

    // 4 thin legs at bottom of torso.
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .pixelRect(x: 8, y: 11, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0)))
    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .pixelRect(x: 10, y: 11, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.25)))
    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .pixelRect(x: 13, y: 11, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.5)))
    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .pixelRect(x: 15, y: 11, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.75)))

    return [
        head, eye, torso,
        earLeft, earRight,
        tail1, tail2,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
