import Foundation
import BabyLogKit

/// Keys and defaults for `@AppStorage`.
///
///     @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
enum Prefs {
    static let selectedBabyID = "selectedBabyID"
    static let volumeUnit = "volumeUnit"
    static let unitSystem = "unitSystem"

    /// `AppearanceMode` raw value.
    static let appearanceMode = "appearanceMode"
    /// Minutes since midnight. Night on a schedule runs from start to end, wrapping past midnight.
    static let nightStartMinutes = "nightStartMinutes"
    static let nightEndMinutes = "nightEndMinutes"
    /// Lower the screen brightness while Night is showing.
    static let dimScreenAtNight = "dimScreenAtNight"
    /// Keep the screen on while the nursing timer is open. Off by default: it costs battery.
    static let keepScreenOnWhileNursing = "keepScreenOnWhileNursing"

    static let defaultAppearanceMode = AppearanceMode.system

    static var defaultVolumeUnit: VolumeUnit {
        Locale.current.measurementSystem == .us ? .ounces : .milliliters
    }

    static var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}
