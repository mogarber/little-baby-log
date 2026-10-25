import SwiftUI
import CoreData
import BabyLogKit

/// Helpers for `#Preview` blocks. Backed by the in-memory sample store.
enum PreviewData {
    static var baby: Baby {
        let context = PersistenceController.preview.viewContext
        let request: NSFetchRequest<Baby> = Baby.fetchRequest()
        if let existing = (try? context.fetch(request))?.first {
            return existing
        }
        return Baby.create(name: "Juniper", birthDate: .now, in: context)
    }

    static func events(limit: Int) -> [LogEvent] {
        let context = PersistenceController.preview.viewContext
        let request: NSFetchRequest<LogEvent> = LogEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }
}

extension View {
    func previewEnvironment() -> some View {
        self
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
            .environment(\.persistence, PersistenceController.preview)
    }
}
