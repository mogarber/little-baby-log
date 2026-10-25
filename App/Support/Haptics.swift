import UIKit
import SwiftUI
import CoreData

enum Haptics {
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

extension UIApplication {
    /// Dismisses the keyboard (decimal pads have no return key).
    static func endEditing() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Calls `action` whenever objects in `context` change (insert, update, delete).
    func onContextChange(_ context: NSManagedObjectContext, perform action: @escaping () -> Void) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
        ) { _ in
            action()
        }
    }
}
