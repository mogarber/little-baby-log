import SwiftUI
import BabyLogKit

private struct PersistenceEnvironmentKey: EnvironmentKey {
    static var defaultValue: PersistenceController { PersistenceController.shared }
}

extension EnvironmentValues {
    var persistence: PersistenceController {
        get { self[PersistenceEnvironmentKey.self] }
        set { self[PersistenceEnvironmentKey.self] = newValue }
    }
}
