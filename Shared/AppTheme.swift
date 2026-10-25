import SwiftUI
import BabyLogKit

/// The app-wide look. `standard` is plain system styling (Light, Dark, System). `night` is the dim, warm, true-black
/// theme for 3 a.m.: black backgrounds (also easy on OLED batteries), amber text instead of white, desaturated colors.
///
/// Views read it from `@Environment(\.appTheme)` and fall back to system styling when it is `standard`, so Light and
/// Dark look exactly as before. Compiled into the widgets too, where it is always `standard`: widgets and Live
/// Activities follow the system appearance.
struct AppTheme: Equatable {
    var isNight: Bool

    static let standard = AppTheme(isNight: false)
    static let night = AppTheme(isNight: true)

    // MARK: Night palette

    /// True black.
    static let nightBackground = Color(red: 0, green: 0, blue: 0)
    /// Rows and cards: a hair above black so they read as surfaces.
    static let nightSurface = Color(red: 0.075, green: 0.058, blue: 0.048)
    /// A step brighter, for controls sitting on a surface (segmented picker, side tiles at rest).
    static let nightRaised = Color(red: 0.125, green: 0.095, blue: 0.075)
    static let nightPrimaryText = Color(red: 0.83, green: 0.60, blue: 0.43)
    static let nightSecondaryText = Color(red: 0.58, green: 0.41, blue: 0.30)
    static let nightTertiaryText = Color(red: 0.40, green: 0.28, blue: 0.21)
    /// Deep warm red-amber.
    static let nightAccent = Color(red: 0.80, green: 0.31, blue: 0.19)
    /// Text and symbols on top of an accent or kind color.
    static let nightOnColor = Color(red: 0.95, green: 0.80, blue: 0.67)
    static let nightSeparator = Color(red: 0.20, green: 0.15, blue: 0.12)

    // MARK: Roles

    /// Screen background behind lists, forms and scroll views.
    var background: Color { isNight ? Self.nightBackground : Color(.systemGroupedBackground) }
    /// Row, card, and tile background.
    var surface: Color { isNight ? Self.nightSurface : Color(.secondarySystemGroupedBackground) }
    /// A control resting on a surface, for example an idle side tile.
    var raised: Color { isNight ? Self.nightRaised : Color(.secondarySystemBackground) }

    var accent: Color { isNight ? Self.nightAccent : .accentColor }
    var onColor: Color { isNight ? Self.nightOnColor : .white }

    var primaryText: Color { isNight ? Self.nightPrimaryText : .primary }

    var primary: AnyShapeStyle { isNight ? AnyShapeStyle(Self.nightPrimaryText) : AnyShapeStyle(.primary) }
    var secondary: AnyShapeStyle { isNight ? AnyShapeStyle(Self.nightSecondaryText) : AnyShapeStyle(.secondary) }
    var tertiary: AnyShapeStyle { isNight ? AnyShapeStyle(Self.nightTertiaryText) : AnyShapeStyle(.tertiary) }

    // MARK: Kind colors

    func color(for kind: EventKind) -> Color {
        guard isNight else { return kind.color }
        // Dim and desaturated, but each stays its own hue so the icons are still told apart half asleep.
        switch kind {
        case .sleep: return Color(red: 0.26, green: 0.28, blue: 0.48)
        case .breastfeed: return Color(red: 0.55, green: 0.24, blue: 0.32)
        case .bottle: return Color(red: 0.57, green: 0.34, blue: 0.14)
        case .solids: return Color(red: 0.27, green: 0.42, blue: 0.25)
        case .diaper: return Color(red: 0.15, green: 0.40, blue: 0.39)
        case .pump: return Color(red: 0.40, green: 0.26, blue: 0.48)
        case .growth: return Color(red: 0.20, green: 0.35, blue: 0.51)
        case .medicine: return Color(red: 0.53, green: 0.21, blue: 0.21)
        }
    }

    func color(for side: BreastSide) -> Color {
        isNight ? color(for: side == .left ? .breastfeed : .pump) : side.color
    }

    /// Destructive actions: a dim red in place of the system red.
    var destructive: Color { isNight ? Color(red: 0.74, green: 0.30, blue: 0.26) : .red }

    /// The three diaper series in Trends.
    var diaperColors: [Color] {
        isNight
            ? [color(for: .diaper), Color(red: 0.45, green: 0.31, blue: 0.20), color(for: .bottle)]
            : [.teal, .brown, .orange]
    }

    /// Chart axis grid lines and rules.
    var gridLine: Color { isNight ? Self.nightSeparator : Color(.separator) }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
