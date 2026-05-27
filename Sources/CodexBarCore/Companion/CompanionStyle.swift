import Foundation

/// Companion 시각 스타일. 현재는 SF Symbol vector 만 지원 — 추후 PNG sprite (RunCat 방식)
/// 등 추가될 여지를 위해 enum 유지.
public enum CompanionStyle: String, Sendable, Codable, CaseIterable {
    case symbol
}
