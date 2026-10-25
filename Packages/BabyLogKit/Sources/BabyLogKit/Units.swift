import Foundation

private func formatNumber(_ value: Double, maxFractionDigits: Int, locale: Locale) -> String {
    value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
}

public enum VolumeUnit: String, CaseIterable, Identifiable, Sendable, Codable {
    case milliliters, ounces

    public static let millilitersPerOunce: Double = 29.5735295625

    public var id: String { rawValue }
    public var symbol: String { self == .milliliters ? "ml" : "oz" }
    public var title: String { self == .milliliters ? "Milliliters (ml)" : "Ounces (oz)" }

    /// Rounded: ml to 1, oz to 0.1.
    public func value(fromMilliliters ml: Double) -> Double {
        switch self {
        case .milliliters: return ml.rounded()
        case .ounces: return (ml / Self.millilitersPerOunce * 10).rounded() / 10
        }
    }

    public func milliliters(from value: Double) -> Double {
        switch self {
        case .milliliters: return value
        case .ounces: return value * Self.millilitersPerOunce
        }
    }

    public func format(milliliters ml: Double, locale: Locale = .current) -> String {
        let number = formatNumber(value(fromMilliliters: ml), maxFractionDigits: self == .ounces ? 1 : 0, locale: locale)
        return "\(number) \(symbol)"
    }
}

public enum UnitSystem: String, CaseIterable, Identifiable, Sendable {
    case metric, imperial

    private static let kilogramsPerPound = 0.45359237
    private static let centimetersPerInch = 2.54

    public var id: String { rawValue }
    public var title: String { self == .metric ? "Metric (kg, cm)" : "Imperial (lb, in)" }
    public var lengthSymbol: String { self == .metric ? "cm" : "in" }

    /// Ounces are rounded to 0.1.
    public static func poundsOunces(fromKilograms kg: Double) -> (pounds: Int, ounces: Double) {
        let totalOunces = (max(0, kg) / kilogramsPerPound * 16 * 10).rounded() / 10
        var pounds = Int((totalOunces / 16).rounded(.down))
        var ounces = ((totalOunces - Double(pounds) * 16) * 10).rounded() / 10
        if ounces >= 16 { pounds += 1; ounces = 0 }
        return (pounds, ounces)
    }

    public static func kilograms(pounds: Double, ounces: Double) -> Double {
        (pounds + ounces / 16) * kilogramsPerPound
    }

    public func lengthValue(fromCentimeters cm: Double) -> Double {
        self == .metric ? cm : cm / Self.centimetersPerInch
    }

    public func centimeters(fromLength value: Double) -> Double {
        self == .metric ? value : value * Self.centimetersPerInch
    }

    public func formatWeight(kilograms kg: Double, locale: Locale = .current) -> String {
        switch self {
        case .metric:
            return "\(formatNumber(kg, maxFractionDigits: 2, locale: locale)) kg"
        case .imperial:
            let (pounds, ounces) = Self.poundsOunces(fromKilograms: kg)
            let oz = formatNumber(ounces, maxFractionDigits: 1, locale: locale)
            return "\(pounds.formatted(.number.locale(locale))) lb \(oz) oz"
        }
    }

    public func formatLength(centimeters cm: Double, locale: Locale = .current) -> String {
        "\(formatNumber(lengthValue(fromCentimeters: cm), maxFractionDigits: 1, locale: locale)) \(lengthSymbol)"
    }
}
