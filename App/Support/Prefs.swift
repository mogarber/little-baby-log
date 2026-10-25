import Foundation
import BabyLogKit

/// Keys and defaults for `@AppStorage`.
///
///     @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
enum Prefs {
    static let selectedBabyID = "selectedBabyID"
    static let volumeUnit = "volumeUnit"
    static let unitSystem = "unitSystem"

    static var defaultVolumeUnit: VolumeUnit {
        Locale.current.measurementSystem == .us ? .ounces : .milliliters
    }

    static var defaultUnitSystem: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}
