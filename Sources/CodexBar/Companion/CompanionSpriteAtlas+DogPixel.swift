// Sources/CodexBar/Companion/CompanionSpriteAtlas+DogPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogPixelParts: [CompanionPart] = _buildDogPixelParts()
}

// swiftlint:disable function_body_length
private func _buildDogPixelParts() -> [CompanionPart] {
    // 20×16 grid. Dog has droopy ears, shorter legs, upright tail.

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
    }

    func legLift(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -2)
        }
    }

    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        // Dog tail wags fast and wide (-25..+30°)
        let sinVal = sin(phase * 4.0 * Double.pi)
        let normalised = sinVal * 0.5 + 0.5
        let degrees = -25.0 + 55.0 * normalised
        let angle = degrees * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 15, y: 7)
            .rotated(by: angle)
            .translatedBy(x: -15, y: -7)
    }

    func earDrop(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : 1)
        }
    }

    // Head
    let head = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 2, y: 4, width: 5, height: 5),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Snout
    let snout = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 0, y: 6, width: 2, height: 2),
        animation: CompanionPartAnimation(transform: bodyBob))
    // Torso
    let torso = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 3, y: 9, width: 11, height: 3),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Droopy ears (longer, drooping down beside head)
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .pixelRect(x: 2, y: 3, width: 1, height: 3),
        animation: CompanionPartAnimation(transform: earDrop(offset: 0)))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .pixelRect(x: 6, y: 3, width: 1, height: 3),
        animation: CompanionPartAnimation(transform: earDrop(offset: 0.5)))

    // Legs
    let leg1 = CompanionPart(
        kind: .leg(index: 1),
        drawCommand: .pixelRect(x: 4, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0)))
    let leg2 = CompanionPart(
        kind: .leg(index: 2),
        drawCommand: .pixelRect(x: 6, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.25)))
    let leg3 = CompanionPart(
        kind: .leg(index: 3),
        drawCommand: .pixelRect(x: 11, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.5)))
    let leg4 = CompanionPart(
        kind: .leg(index: 4),
        drawCommand: .pixelRect(x: 13, y: 12, width: 1, height: 2),
        animation: CompanionPartAnimation(transform: legLift(offset: 0.75)))

    // Tail (upright stub)
    let tail1 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 14, y: 7, width: 1, height: 3),
        animation: CompanionPartAnimation(transform: tailWag))
    let tail2 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 15, y: 6, width: 1, height: 1),
        animation: CompanionPartAnimation(transform: tailWag))

    return [head, snout, torso, earLeft, earRight, leg1, leg2, leg3, leg4, tail1, tail2]
}
// swiftlint:enable function_body_length
