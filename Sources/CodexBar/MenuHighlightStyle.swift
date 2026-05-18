import SwiftUI

private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }
}

enum MenuHighlightStyle {
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    // Card content keeps its natural colors on hover so the embedded chart,
    // progress bars, and labels stay readable. Hover is communicated via a
    // subtle accent-tinted background only (see selectionBackground).
    static func primary(_ highlighted: Bool) -> Color {
        self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        Color(nsColor: .systemRed)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        Color(nsColor: .tertiaryLabelColor).opacity(0.22)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        // Subtle accent tint instead of the saturated system selection color
        // so the embedded chart bars and cost summary remain visible on hover.
        highlighted ? Color(nsColor: .controlAccentColor).opacity(0.15) : .clear
    }
}
