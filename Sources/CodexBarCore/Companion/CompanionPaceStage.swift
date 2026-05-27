import Foundation

public enum CompanionPaceStage: String, CaseIterable, Sendable, Codable {
    case idle
    case slow
    case normal
    case fast
    case burst

    /// Animation duration per cycle. Smaller = faster.
    public var frameInterval: TimeInterval {
        switch self {
        case .idle:   return 20.0   // body breathing only
        case .slow:   return 1.2
        case .normal: return 0.6
        case .fast:   return 0.3
        case .burst:  return 0.15
        }
    }
}
