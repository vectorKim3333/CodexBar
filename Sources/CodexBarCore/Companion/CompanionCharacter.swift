import Foundation

/// 메뉴바 Companion 의 캐릭터 종류. 모두 SF Symbol vector asset 기반이라 어떤 크기에서도
/// 깨끗하고 동물/사물 형태가 명확히 인식됨. frame 단위 transform (rotate + translateY) 으로
/// "통통 튀는" 미세 motion 표현.
///
/// 새 case 추가 절차:
///   1. 여기에 case 추가 (rawValue 안정성 위해 SF Symbol 점-표기는 camelCase 로)
///   2. `CompanionSpriteFrameRenderer.symbolName(for:)` 에 SF Symbol 이름 dispatch
///   3. `species` / `style` 매핑 추가
///   4. `companion.character.<case>` 로컬라이제이션 키 추가 (ko/en)
///   5. `PreferencesDisplayPane.characterLabel` + `CompanionMenuBuilder.characterLabel`
///      switch 에 case 추가
public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case dog
    case cat
    case hare
    case tortoise
    case bird
    case figureRun
    case flame
    case boltFill

    public static let `default`: CompanionCharacter = .dog

    public var species: CompanionSpecies {
        switch self {
        case .dog:       return .dog
        case .cat:       return .cat
        case .hare:      return .hare
        case .tortoise:  return .tortoise
        case .bird:      return .bird
        case .figureRun: return .human
        case .flame, .boltFill: return .object
        }
    }

    public var style: CompanionStyle {
        // 모두 SF Symbol vector. ASCII pixel-art 시스템은 1.5.0 에서 폐기됨.
        .symbol
    }
}
