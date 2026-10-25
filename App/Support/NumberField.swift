import SwiftUI

/// A decimal text field backed by a String, parsed with the current locale.
///
/// `TextField(value:format:)` only commits on return and the decimal pad has no return key,
/// so this commits on every keystroke instead. Blank means 0.
struct NumberField: View {
    let title: String
    @Binding private var value: Double
    let unit: String?
    let digits: Int

    @State private var text: String
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double>, unit: String? = nil, digits: Int = 1) {
        self.title = title
        self._value = value
        self.unit = unit
        self.digits = digits
        self._text = State(initialValue: NumberField.format(value.wrappedValue, digits: digits))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(minWidth: 60)
                .font(.title3.weight(.medium))
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: text) { _, newText in
            guard focused, let parsed = NumberField.parse(newText) else { return }
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = NumberField.format(newValue, digits: digits) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = NumberField.format(value, digits: digits) }
        }
    }

    static func format(_ number: Double, digits: Int) -> String {
        guard number > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: number)) ?? ""
    }

    /// Blank → 0. Unparseable (e.g. a lone separator) → nil, meaning "leave the value alone".
    static func parse(_ string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let number = formatter.number(from: trimmed) {
            return max(0, number.doubleValue)
        }
        if let fallback = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return max(0, fallback)
        }
        return nil
    }
}
