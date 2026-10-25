import SwiftUI
import UIKit
import BabyLogKit

/// Applies the Appearance setting to the whole window: the color scheme, the Night theme (through
/// `\.appTheme`), the bar colors, and dimming the screen.
///
/// Scheduled Night does not poll. It works out the next moment the schedule flips and sleeps until exactly then,
/// once, and only while the app is in the foreground. It looks again when the app becomes active and when the
/// clock or time zone changes.
struct AppearanceHost: ViewModifier {
    @AppStorage(Prefs.appearanceMode) private var mode: AppearanceMode = Prefs.defaultAppearanceMode
    @AppStorage(Prefs.nightStartMinutes) private var startMinutes = NightSchedule.defaultStartMinutes
    @AppStorage(Prefs.nightEndMinutes) private var endMinutes = NightSchedule.defaultEndMinutes
    @AppStorage(Prefs.dimScreenAtNight) private var dimScreen = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var appearance: ResolvedAppearance
    /// Bumped when the clock or time zone changes, to restart the wait for the next transition.
    @State private var clockChanges = 0

    init() {
        _appearance = State(initialValue: Self.currentAppearance())
    }

    private var schedule: NightSchedule {
        NightSchedule(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    private var theme: AppTheme { appearance.isNight ? .night : .standard }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark, .night: return .dark
        }
    }

    private var shouldDim: Bool {
        appearance.isNight && dimScreen && mode.canShowNight && scenePhase == .active
    }

    /// What decides when to wait again.
    private struct WaitKey: Equatable {
        var mode: AppearanceMode
        var start: Int
        var end: Int
        var isActive: Bool
        var clockChanges: Int
    }

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, theme)
            .preferredColorScheme(colorScheme)
            .tint(appearance.isNight ? theme.accent : nil)
            .task(id: WaitKey(mode: mode, start: startMinutes, end: endMinutes, isActive: scenePhase == .active, clockChanges: clockChanges)) {
                await trackSchedule()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                clockChanges += 1
            }
            .onChange(of: appearance.isNight, initial: true) { _, isNight in
                BarAppearance.apply(night: isNight)
            }
            .onChange(of: shouldDim, initial: true) { _, dim in
                ScreenDimmer.shared.setDimmed(dim)
            }
    }

    /// Re-evaluates now, then sleeps until the schedule's next transition (a single wait, no polling).
    private func trackSchedule() async {
        refresh()
        guard scenePhase == .active else { return }
        while !Task.isCancelled, let next = mode.nextTransition(schedule: schedule, after: .now) {
            // At least a second, so a wake-up that lands just short of the boundary can't spin.
            let wait = max(1, next.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            refresh()
        }
    }

    private func refresh() {
        let current = mode.resolved(schedule: schedule, at: .now)
        if current != appearance { appearance = current }
    }

    private static func currentAppearance() -> ResolvedAppearance {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: Prefs.appearanceMode).flatMap(AppearanceMode.init(rawValue:)) ?? Prefs.defaultAppearanceMode
        let start = defaults.object(forKey: Prefs.nightStartMinutes) as? Int ?? NightSchedule.defaultStartMinutes
        let end = defaults.object(forKey: Prefs.nightEndMinutes) as? Int ?? NightSchedule.defaultEndMinutes
        return mode.resolved(schedule: NightSchedule(startMinutes: start, endMinutes: end), at: .now)
    }
}

extension View {
    /// Applies Settings > Appearance to this window. Put it on the root of a scene.
    func appearanceHost() -> some View {
        modifier(AppearanceHost())
    }
}
