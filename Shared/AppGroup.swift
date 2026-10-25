import Foundation
import CoreData
import BabyLogKit

/// The App Group shared by the app and the widget extension. It holds the Core Data store (opened only by
/// the app) and the JSON snapshot the widgets read.
enum AppGroup {
    /// Read from Info.plist key `LBLAppGroup` (`$(APP_GROUP_ID)`); nil when empty or never expanded.
    static var identifier: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LBLAppGroup") as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value.isEmpty || value.contains("$(")) ? nil : value
    }

    /// nil when the group isn't available (missing entitlement or a misconfigured build).
    static var containerURL: URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// `<group>/widget-snapshot.json`
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    /// `<group>/Library/Application Support`, where the Core Data store lives. nil when the group is unavailable.
    static var storeDirectory: URL? {
        containerURL?.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
