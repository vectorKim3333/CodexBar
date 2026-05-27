import Foundation

public struct PlanUtilizationHistoryEntry: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}
