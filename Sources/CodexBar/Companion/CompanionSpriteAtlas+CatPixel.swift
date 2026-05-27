// Sources/CodexBar/Companion/CompanionSpriteAtlas+CatPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _catPixelParts: [CompanionPart] = _buildCatPixelParts()
}

// swiftlint:disable function_body_length
private func _buildCatPixelParts() -> [CompanionPart] {
    // Coordinate space: 20×16. Cat sits left of center, tail to the right.
    // Body bobs ±1px vertically with phase. Legs alternate up/down. Ears rotate.

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        // Two-step (steps(2)): 0→0px, 0.5→-1px
        CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
    }

    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        // Sinusoidal rotation between -15° and +20°
        let sinVal = sin(phase * 2.0 * Double.pi)
        let normalised = sinVal * 0.5 + 0.5           // 0...1
        let degrees = -15.0 + 35.0 * normalised       // -15°...+20°
        let angle = degrees * Double.pi / 180.0
        return CGAffineTransform(rotationAngle: angle)
    }

    func legTransform(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            // Lift the leg in the second half of the local cycle
            return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -2)
        }
    }

    func earFlick(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            let angle = (local < 0.5 ? 0.0 : -15.0) * .pi / 180
            return CGAffineTransform(rotationAngle: angle)
        }
    }

    // Body — head
    let head = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 2, y: 5, width: 5, height: 4),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Body — torso
    let torso = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 3, y: 9, width: 11, height: 3),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Ears
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .pixelRect(x: 2, y: 3, width: 2, height: 2),
        animation: CompanionPartAnimation(phaseOffset: 0.125, transform: earFlick(offset: 0)))

    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .pixelRect(x: 5, y: 3, width: 2, height: 2),
        animation: CompanionPartAnimation(phaseOffset: 0.625, transform: earFlick(offset: 0)))

    // Legs (front-left, front-right, back-left, back-right)
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .pixelRect(x: 3, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legTransform(offset: 0)))

    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .pixelRect(x: 6, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legTransform(offset: 0.25)))

    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .pixelRect(x: 10, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legTransform(offset: 0.5)))

    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .pixelRect(x: 13, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legTransform(offset: 0.75)))

    // Tail (two pixel rects)
    let tail1 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 14, y: 6, width: 3, height: 1),
        animation: CompanionPartAnimation(transform: tailWag))

    let tail2 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 16, y: 7, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: tailWag))

    return [head, torso, earLeft, earRight, leg1, leg2, leg3, leg4, tail1, tail2]
}
// swiftlint:enable function_body_length
