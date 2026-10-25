import CoreData
import os

enum BabyLogLog {
    static let persistence = Logger(subsystem: "LittleBabyLog", category: "persistence")
}

extension NSManagedObjectContext {
    /// Saves when there are changes. Logs errors; never crashes and never rolls back.
    /// Returns `false` only if the save failed (`true` when saved or nothing to save).
    @discardableResult
    public func saveIfNeeded() -> Bool {
        var succeeded = true
        performAndWait {
            guard hasChanges else { return }
            do {
                try save()
            } catch {
                BabyLogLog.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
                succeeded = false
            }
        }
        return succeeded
    }
}
