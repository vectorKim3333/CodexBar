import AppKit
import CodexBarCore
import CoreGraphics
import Foundation

/// SF Symbols 기반 frame renderer.
///
/// Apple 의 hand-crafted vector 동물 심볼 (예: `dog` / `cat` / `hare`) 을 base 로 쓰고
/// frame 마다 `CGAffineTransform` (rotate + translateY) 을 적용해 "달리는" 느낌의
/// bobbing motion 을 만든다.
///
/// 이전엔 ASCII art 픽셀 단위 hand-paint 였지만 메뉴바 작은 크기에선 detail 표현이 불가능했음.
/// SF Symbols 는 vector + Apple 디자이너 quality 라 어떤 size 에서도 강아지로 인식됨.
/// 다리 단위 dynamic motion 은 표현 불가 (정적 심볼이 base 라서) — 대신 전체 transform 으로
/// "통통 튀며 앞으로 가는" 느낌. RunCat 의 frame-by-frame 다리 모션과는 다른 종류의 motion.
@MainActor
enum CompanionSpriteFrameRenderer {
    private static let cache = NSCache<NSString, NSImage>()
    private static let defaultSize = NSSize(width: 28, height: 22)
    /// symbol 자체의 pointSize. image size 보다 작게 둬서 rotate + translateY 시 가장자리 잘림 방지.
    /// image height 22 - symbol 14 = 여유 8px → translateY -5 + rotate corner ~1.5px 까지 안전.
    private static let symbolPointSize: CGFloat = 14
    private static let frameCount = 5

    /// 5 frame dramatic bobbing — "통통 튀는" 범위 확대 (이전 ±4°/-2.5 → ±10°/-5).
    ///
    /// 사이클: rest → 앞으로 강하게 기울며 점프 → peak (수평, 최고점) → 뒤로 강하게 기울며
    /// 하강 → 착지 직전.
    private static let frameTransforms: [(rotationDegrees: CGFloat, translateY: CGFloat)] = [
        (0, 0),       // frame 0 — rest / 착지 직후
        (10, -3),     // frame 1 — 앞으로 기울며 점프 상승
        (0, -5),      // frame 2 — 점프 peak, 수평
        (-10, -3),    // frame 3 — 뒤로 기울며 하강
        (0, -1),      // frame 4 — 착지 직전
    ]

    static func render(
        character: CompanionCharacter,
        frameIndex: Int,
        size: NSSize = defaultSize) -> NSImage
    {
        let safeIndex = ((frameIndex % Self.frameCount) + Self.frameCount) % Self.frameCount
        let key = "\(character.rawValue)|\(safeIndex)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = self.cache.object(forKey: key) { return cached }

        let image = self.drawFrame(character: character, frameIndex: safeIndex, size: size)
        image.isTemplate = true
        self.cache.setObject(image, forKey: key)
        return image
    }

    static func frameCount(for _: CompanionCharacter) -> Int {
        Self.frameCount
    }

    static func clearCache() {
        self.cache.removeAllObjects()
    }

    // MARK: - SF Symbol resolution

    private static func symbolName(for character: CompanionCharacter) -> String {
        switch character {
        case .dog:       return "dog"
        case .cat:       return "cat"
        case .hare:      return "hare"
        case .tortoise:  return "tortoise"
        case .bird:      return "bird"
        case .figureRun: return "figure.run"
        case .flame:     return "flame"
        case .boltFill:  return "bolt.fill"
        }
    }

    /// Fallback chain — macOS 버전이 낮아 "dog" 가 없으면 보편적인 `pawprint.fill` 로 대체.
    /// 둘 다 실패하면 nil → drawFrame 이 빈 NSImage 반환.
    private static func resolveSymbol(name: String) -> NSImage? {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return img
        }
        return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)
    }

    // MARK: - Drawing

    private static func drawFrame(character: CompanionCharacter, frameIndex: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext,
              let symbol = self.resolveSymbol(name: self.symbolName(for: character))
        else { return image }

        // SF Symbol pointSize 명시 — image size 보다 작게 둬서 rotate 후에도 가장자리 잘림 방지.
        let config = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .medium)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol

        // 5 frame bobbing — image 중심 기준으로 rotate 후 translateY.
        let transform = Self.frameTransforms[frameIndex]
        let centerX = size.width / 2
        let centerY = size.height / 2
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: transform.rotationDegrees * .pi / 180)
        ctx.translateBy(x: -centerX, y: -centerY)
        ctx.translateBy(x: 0, y: transform.translateY)

        // Symbol image 를 정중앙에 fit. symbol.size 가 pointSize 기준 비례 자동 계산됨.
        let symbolSize = configured.size
        let drawRect = CGRect(
            x: (size.width - symbolSize.width) / 2,
            y: (size.height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height)
        configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)

        return image
    }
}
