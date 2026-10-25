import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct CSVExporterTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func headerAndSorting() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: TestSupport.utc(2026, 1, 1), in: ctx)
        let later = LogEvent.create(kind: .diaper, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        later.diaperKind = .wet
        let earlier = LogEvent.create(kind: .sleep, for: baby, start: TestSupport.utc(2026, 3, 10, 1), in: ctx)
        earlier.endDate = TestSupport.utc(2026, 3, 10, 2, 30)

        let csv = CSVExporter.csv(for: [later, earlier], timeZone: utc)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == CSVExporter.columns.joined(separator: ","))
        #expect(lines.count == 4) // header + 2 rows + trailing empty
        #expect(lines[1].hasPrefix("Ada,Sleep,2026-03-10T01:00:00Z,2026-03-10T02:30:00Z,90,"))
        #expect(lines[2].hasPrefix("Ada,Diaper,2026-03-10T09:00:00Z,,,"))
        #expect(lines[2].contains(",Wet,"))
        for line in lines.dropLast() {
            #expect(line.components(separatedBy: ",").count == CSVExporter.columns.count)
        }
    }

    @Test func timeZoneOffset() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: ctx)
        let e = LogEvent.create(kind: .diaper, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        e.diaperKind = .dry
        let csv = CSVExporter.csv(for: [e], timeZone: TimeZone(secondsFromGMT: -5 * 3600)!)
        #expect(csv.contains("2026-03-10T04:00:00-05:00"))
    }

    @Test func quoting() {
        #expect(CSVExporter.field("plain") == "plain")
        #expect(CSVExporter.field("a,b") == "\"a,b\"")
        #expect(CSVExporter.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExporter.field("line1\nline2") == "\"line1\nline2\"")
    }

    @Test func formulaInjectionGuard() {
        #expect(CSVExporter.guarded("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSVExporter.guarded("+1") == "'+1")
        #expect(CSVExporter.guarded("-1") == "'-1")
        #expect(CSVExporter.guarded("@cmd") == "'@cmd")
        #expect(CSVExporter.guarded("fine=ok") == "fine=ok")
        #expect(CSVExporter.guarded("") == "")

        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "=EVIL()", birthDate: .now, in: ctx)
        let e = LogEvent.create(kind: .medicine, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        e.medicineName = "@drug"
        e.dose = "2,5 ml"
        e.notes = "He said \"ok\"\n+later"
        let csv = CSVExporter.csv(for: [e], timeZone: utc)
        #expect(csv.contains("'=EVIL(),Medicine"))
        #expect(csv.contains(",'@drug,\"2,5 ml\","))
        #expect(csv.contains("\"He said \"\"ok\"\"\n+later\""))
    }

    @Test func numbersUseDotAndTrimZeros() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: .now, in: ctx)
        let e = LogEvent.create(kind: .growth, for: baby, start: TestSupport.utc(2026, 3, 10, 9), in: ctx)
        e.weightKg = 4.25; e.lengthCm = 55.5; e.headCm = 37
        let csv = CSVExporter.csv(for: [e], timeZone: utc)
        #expect(csv.contains(",4.25,55.5,37,"))
    }
}
