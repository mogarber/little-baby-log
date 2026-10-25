import SwiftUI

/// A small battery icon and one sentence saying what a setting does to battery life. Use it under any setting
/// that costs (or saves) battery, right where the setting is turned on.
struct BatteryImpactNote: View {
    enum Effect {
        /// The setting uses more battery.
        case costs
        /// The setting saves battery.
        case saves

        var symbolName: String {
            switch self {
            case .costs: return "battery.25percent"
            case .saves: return "battery.100percent"
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .costs: return "Battery: "
            case .saves: return "Saves battery: "
            }
        }
    }

    @Environment(\.appTheme) private var theme

    let text: String
    var effect: Effect = .costs

    init(_ text: String, effect: Effect = .costs) {
        self.text = text
        self.effect = effect
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: effect.symbolName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(theme.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effect.accessibilityPrefix + text)
    }
}

#Preview {
    Form {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Keep screen on during nursing timer", isOn: .constant(false))
                BatteryImpactNote("Keeps your screen on while the timer is open, which uses more battery.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Dim screen at night", isOn: .constant(true))
                BatteryImpactNote("Lowers the brightness while Night is showing, which saves battery.", effect: .saves)
            }
        }
    }
}
