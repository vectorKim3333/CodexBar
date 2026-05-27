import Foundation

/// Companion 동물/사물 카테고리. 사실상 카테고리 metadata 라 picker UI 에는 직접 안 쓰이지만
/// 추후 species 별 motion preset (동물은 점프 / object 는 진동 등) 에 활용 가능.
public enum CompanionSpecies: String, Sendable, Codable, CaseIterable {
    case dog
    case cat
    case hare
    case tortoise
    case bird
    case human
    case object
}
