import Foundation

public enum CompanionCharacter: String, CaseIterable, Sendable, Codable {
    case catPixel
    case catLine
    case dogPixel
    case dogLine

    public static let `default`: CompanionCharacter = .catPixel

    public var species: CompanionSpecies {
        switch self {
        case .catPixel, .catLine: return .cat
        case .dogPixel, .dogLine: return .dog
        }
    }

    public var style: CompanionStyle {
        switch self {
        case .catPixel, .dogPixel: return .pixel
        case .catLine, .dogLine:   return .line
        }
    }
}
