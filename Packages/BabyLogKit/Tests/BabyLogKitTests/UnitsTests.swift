import Testing
import Foundation
@testable import BabyLogKit

struct UnitsTests {
    @Test func volumeRoundTrip() {
        let ml = VolumeUnit.ounces.milliliters(from: 4)
        #expect(abs(ml - 118.294118) < 0.001)
        #expect(VolumeUnit.ounces.value(fromMilliliters: ml) == 4.0)
        #expect(VolumeUnit.milliliters.value(fromMilliliters: 119.6) == 120)
        #expect(VolumeUnit.milliliters.milliliters(from: 90) == 90)
        #expect(VolumeUnit.millilitersPerOunce == 29.5735295625)
    }

    @Test func volumeFormatting() {
        let us = TestSupport.enUS
        #expect(VolumeUnit.milliliters.format(milliliters: 120, locale: us) == "120 ml")
        #expect(VolumeUnit.ounces.format(milliliters: 118.294118, locale: us) == "4 oz")
        #expect(VolumeUnit.ounces.format(milliliters: 133.07, locale: us) == "4.5 oz")
        #expect(VolumeUnit.milliliters.format(milliliters: 1200, locale: us) == "1,200 ml")
    }

    @Test func formattingUsesLocale() {
        let de = Locale(identifier: "de_DE")
        #expect(VolumeUnit.ounces.format(milliliters: 133.07, locale: de) == "4,5 oz")
        #expect(UnitSystem.metric.formatWeight(kilograms: 4.25, locale: de) == "4,25 kg")
    }

    @Test func weightRoundTrip() {
        let kg = UnitSystem.kilograms(pounds: 9, ounces: 6)
        let (lb, oz) = UnitSystem.poundsOunces(fromKilograms: kg)
        #expect(lb == 9)
        #expect(oz == 6.0)
        #expect(abs(kg - 4.2524) < 0.001)
    }

    @Test func poundsOuncesCarry() {
        // 15.98 oz rounds to 16.0 -> 1 lb 0 oz
        let kg = UnitSystem.kilograms(pounds: 0, ounces: 15.98)
        let (lb, oz) = UnitSystem.poundsOunces(fromKilograms: kg)
        #expect(lb == 1)
        #expect(oz == 0)
        let zero = UnitSystem.poundsOunces(fromKilograms: 0)
        #expect(zero.pounds == 0 && zero.ounces == 0)
    }

    @Test func weightFormatting() {
        let us = TestSupport.enUS
        #expect(UnitSystem.metric.formatWeight(kilograms: 4.25, locale: us) == "4.25 kg")
        #expect(UnitSystem.metric.formatWeight(kilograms: 4, locale: us) == "4 kg")
        #expect(UnitSystem.imperial.formatWeight(kilograms: UnitSystem.kilograms(pounds: 9, ounces: 6), locale: us) == "9 lb 6 oz")
        #expect(UnitSystem.imperial.formatWeight(kilograms: UnitSystem.kilograms(pounds: 9, ounces: 6.5), locale: us) == "9 lb 6.5 oz")
    }

    @Test func lengthConversionAndFormatting() {
        let us = TestSupport.enUS
        #expect(UnitSystem.metric.lengthValue(fromCentimeters: 55.5) == 55.5)
        #expect(abs(UnitSystem.imperial.lengthValue(fromCentimeters: 55.5) - 21.8504) < 0.001)
        #expect(abs(UnitSystem.imperial.centimeters(fromLength: 21.8504) - 55.5) < 0.001)
        #expect(UnitSystem.metric.formatLength(centimeters: 55.5, locale: us) == "55.5 cm")
        #expect(UnitSystem.imperial.formatLength(centimeters: 55.5, locale: us) == "21.9 in")
        #expect(UnitSystem.metric.lengthSymbol == "cm")
        #expect(UnitSystem.imperial.lengthSymbol == "in")
    }
}
