import SwiftUI

/// View helpers that apply `AppTheme`. Every one is a no-op in the standard theme, so Light, Dark and System keep
/// their stock look.
/// At night the default text color is amber instead of white. This is applied per screen, and only at night, rather
/// than once at the root: an explicit foreground style on an ancestor changes how stock controls render in Light and
/// Dark (a prominent button's label turns black), and the standard theme must stay exactly as it was. The branch
/// swaps only the screen's content; the sheets and state around it are untouched when Night turns on or off.
private struct ThemedForeground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.isNight {
            content.foregroundStyle(AppTheme.nightPrimaryText)
        } else {
            content
        }
    }
}

private struct ThemedList: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.isNight {
            content
                .foregroundStyle(AppTheme.nightPrimaryText)
                .scrollContentBackground(.hidden)
                .background { theme.background.ignoresSafeArea() }
        } else {
            content
        }
    }
}

private struct ThemedSection: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.isNight ? theme.surface : nil)
            .listRowSeparatorTint(theme.isNight ? AppTheme.nightSeparator : nil)
    }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.isNight {
            content
                .foregroundStyle(AppTheme.nightPrimaryText)
                .background { theme.background.ignoresSafeArea() }
        } else {
            content
        }
    }
}

/// Text or symbols sitting on a tinted button or tile. White in the standard theme (left to the system), a soft
/// amber at night.
private struct ThemedOnColor: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.isNight {
            content.foregroundStyle(theme.onColor)
        } else {
            content
        }
    }
}

/// A destructive button label: the system's red role color in the standard theme, a dim red at night (where the
/// theme's amber would otherwise cover it).
private struct ThemedDestructive: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.isNight {
            content.foregroundStyle(theme.destructive)
        } else {
            content
        }
    }
}

extension View {
    func themedDestructive() -> some View { modifier(ThemedDestructive()) }

    /// A `List` or `Form`: black background at night.
    func themedList() -> some View { modifier(ThemedList()) }

    /// A `Section` of a `List` or `Form`: near-black rows at night.
    func themedSection() -> some View { modifier(ThemedSection()) }

    /// Amber default text at night, for a screen that already sets its own background.
    func themedForeground() -> some View { modifier(ThemedForeground()) }

    /// A `ScrollView` or other plain screen: black background and amber text at night.
    func themedScreen() -> some View { modifier(ThemedScreen()) }

    func themedOnColor() -> some View { modifier(ThemedOnColor()) }
}
