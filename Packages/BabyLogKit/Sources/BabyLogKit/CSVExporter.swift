import Foundation

public enum CSVExporter {
    public static let columns: [String] = [
        "Baby", "Type", "Start", "End", "Duration (min)",
        "Left (min)", "Right (min)",
        "Amount (ml)", "Contents", "Food", "Diaper",
        "Pumped left (ml)", "Pumped right (ml)",
        "Weight (kg)", "Length (cm)", "Head (cm)",
        "Medicine", "Dose", "Notes",
    ]

    /// RFC 4180 quoting (CRLF line endings); ISO-8601 dates with offset; text fields starting with
    /// `= + - @` (or tab/CR) get a leading `'` (formula injection). Rows are sorted by start date ascending.
    public static func csv(for events: [LogEvent], timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]

        func date(_ d: Date?) -> String { d.map { formatter.string(from: $0) } ?? "" }

        var lines = [columns.map(field).joined(separator: ",")]
        let sorted = events.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        for event in sorted {
            let kind = event.kind
            var row = [String](repeating: "", count: columns.count)
            row[0] = guarded(event.baby?.displayName ?? "")
            row[1] = kind.title
            row[2] = date(event.startDate)
            row[3] = date(event.endDate)
            if kind.hasDuration, event.endDate != nil || kind == .breastfeed {
                row[4] = number(event.duration() / 60)
            }
            switch kind {
            case .breastfeed:
                row[5] = number(event.leftSeconds / 60)
                row[6] = number(event.rightSeconds / 60)
            case .bottle:
                row[7] = number(event.amountML)
                row[8] = event.bottleContent?.title ?? ""
            case .solids:
                row[9] = guarded(event.foodName ?? "")
            case .diaper:
                row[10] = event.diaperKind?.title ?? ""
            case .pump:
                row[11] = number(event.leftML)
                row[12] = number(event.rightML)
            case .growth:
                row[13] = number(event.weightKg)
                row[14] = number(event.lengthCm)
                row[15] = number(event.headCm)
            case .medicine:
                row[16] = guarded(event.medicineName ?? "")
                row[17] = guarded(event.dose ?? "")
            case .sleep:
                break
            }
            row[18] = guarded(event.notes ?? "")
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Prefixes a quote so spreadsheets don't evaluate the cell as a formula.
    static func guarded(_ text: String) -> String {
        guard let first = text.first, "=+-@\t\r".contains(first) else { return text }
        return "'" + text
    }

    /// RFC 4180 field quoting.
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Locale-independent number, up to 2 decimals, blank for 0.
    private static func number(_ value: Double) -> String {
        guard value != 0 else { return "" }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
