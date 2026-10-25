import CoreData
import Foundation
@testable import BabyLogKit

enum TestSupport {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day
        parts.hour = hour; parts.minute = minute; parts.second = second
        return utcCalendar.date(from: parts)!
    }

    static let enUS = Locale(identifier: "en_US")

    @MainActor
    static func makeContext() -> (PersistenceController, NSManagedObjectContext) {
        let persistence = PersistenceController(inMemory: true)
        return (persistence, persistence.viewContext)
    }
}
