import UIKit

/// Lowers the screen brightness while Night is showing, and puts the person's own level back afterwards.
///
/// Battery: on an OLED the display is the biggest consumer, so a dimmer screen at night is a real saving.
/// It only ever runs while the app is in the foreground; iOS also restores the system brightness by itself when
/// the app goes away, so a crash can't leave the phone dim.
///
/// Uses the window scene's screen. `UIScreen.main` is deprecated as of iOS 26.
@MainActor
final class ScreenDimmer {
    static let shared = ScreenDimmer()

    /// How dim "dim" is. The screen is only ever lowered to this, never raised to it.
    static let dimLevel: CGFloat = 0.2

    private weak var screen: UIScreen?
    private var originalBrightness: CGFloat?
    private var dimmedBrightness: CGFloat?

    var isDimmed: Bool { originalBrightness != nil }

    func setDimmed(_ dimmed: Bool) {
        if dimmed { dim() } else { restore() }
    }

    private func dim() {
        guard !isDimmed, let screen = Self.activeScreen() else { return }
        let current = screen.brightness
        self.screen = screen
        originalBrightness = current
        screen.brightness = min(current, Self.dimLevel)
        dimmedBrightness = screen.brightness
    }

    private func restore() {
        defer {
            originalBrightness = nil
            dimmedBrightness = nil
            screen = nil
        }
        guard let screen, let originalBrightness, let dimmedBrightness else { return }
        // If the person moved the brightness slider while we were dimmed, that is their choice now.
        guard abs(screen.brightness - dimmedBrightness) < 0.03 else { return }
        screen.brightness = originalBrightness
    }

    private static func activeScreen() -> UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}
