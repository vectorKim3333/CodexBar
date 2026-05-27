// Sources/CodexBar/Companion/CompanionSpriteAtlas+DogPixel.swift
import CoreGraphics
import Foundation

extension CompanionSpriteAtlas {
    static let _dogPixelParts: [CompanionPart] = _buildDogPixelParts()
}

// swiftlint:disable function_body_length
private func _buildDogPixelParts() -> [CompanionPart] {
    // 20×16 pixel dog, profile facing left.
    //  - Chunky snout sticks out left from the head (cat has none)
    //  - Floppy ears DROOP DOWN beside the head (cat ears point up)
    //  - Stockier torso, shorter legs
    //  - Short upright tail

    let bodyBob: @Sendable (Double) -> CGAffineTransform = { phase in
        CGAffineTransform(translationX: 0, y: phase < 0.5 ? 0 : -1)
    }

    func legLift(offset: Double) -> @Sendable (Double) -> CGAffineTransform {
        return { phase in
            let local = fmod(phase + offset, 1.0)
            return CGAffineTransform(translationX: 0, y: local < 0.5 ? 0 : -1)
        }
    }

    // Dog tail wag: ±20° at 2× frequency (faster than cat).
    let tailWag: @Sendable (Double) -> CGAffineTransform = { phase in
        let angle = sin(phase * 4.0 * Double.pi) * 20.0 * Double.pi / 180.0
        return CGAffineTransform.identity
            .translatedBy(x: 16, y: 8)
            .rotated(by: angle)
            .translatedBy(x: -16, y: -8)
    }

    // Ears just bob with body — no rotation, looks calmer.
    let earStill: @Sendable (Double) -> CGAffineTransform = { _ in .identity }

    // Snout — a small block sticking out left of the head.
    let snout = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 0, y: 7, width: 3, height: 3),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Head — larger square block above and behind the snout.
    let head = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 3, y: 4, width: 5, height: 5),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Eye dot
    let eye = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 5, y: 6, width: 1, height: 1),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Torso — extends right from head, slightly heavier than the cat's.
    let torso = CompanionPart(
        kind: .body,
        drawCommand: .pixelRect(x: 8, y: 7, width: 8, height: 4),
        animation: CompanionPartAnimation(transform: bodyBob))

    // Floppy ears — vertical pixel strips that hang down beside the head
    // (they overlap the head rect a little, which is fine in template mode).
    let earLeft = CompanionPart(
        kind: .ear(side: .left),
        drawCommand: .pixelRect(x: 3, y: 3, width: 1, height: 4),
        animation: CompanionPartAnimation(transform: earStill))
    let earRight = CompanionPart(
        kind: .ear(side: .right),
        drawCommand: .pixelRect(x: 7, y: 3, width: 1, height: 4),
        animation: CompanionPartAnimation(transform: earStill))

    // Short upright tail (2 pixel segments going up + slightly back).
    let tail1 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 16, y: 5, width: 1, height: 4),
        animation: CompanionPartAnimation(transform: tailWag))
    let tail2 = CompanionPart(
        kind: .tail,
        drawCommand: .pixelRect(x: 17, y: 4, width: 1, height: 1),
        animation: CompanionPartAnimation(transform: tailWag))

    // 4 short legs.
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
        snout, head, eye, torso,
        earLeft, earRight,
        tail1, tail2,
        leg1, leg2, leg3, leg4,
    ]
}
// swiftlint:enable function_body_length
