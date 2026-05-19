import Foundation

/// Controls how the menu-bar pill renders the countdown to the next reset.
enum MenuBarTimeFormat: String, CaseIterable, Identifiable {
    /// Ceiling, with `~` prefix. e.g. 1h 45m → "~2h". Default.
    case approximate
    /// Hours + minutes, no rounding. e.g. 1h 45m → "1h 45m".
    case precise
    /// Floor with `+` suffix. e.g. 1h 45m → "1h+".
    case floor

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .approximate: L("time_format_approximate")
        case .precise: L("time_format_precise")
        case .floor: L("time_format_floor")
        }
    }
}
