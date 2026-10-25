import Foundation
import Testing
@testable import BabyLogKit

struct PredictionsTextTests {
    @Test func ageLabels() {
        #expect(PredictionText.ageLabel(ageDays: 0) == "newborns")
        #expect(PredictionText.ageLabel(ageDays: 6) == "newborns")
        #expect(PredictionText.ageLabel(ageDays: 10) == "10 days")
        #expect(PredictionText.ageLabel(ageDays: 14) == "2 weeks")
        #expect(PredictionText.ageLabel(ageDays: 49) == "7 weeks")
        #expect(PredictionText.ageLabel(ageDays: 83) == "11 weeks")
        #expect(PredictionText.ageLabel(ageDays: 84) == "2 months")
        #expect(PredictionText.ageLabel(ageDays: 190) == "6 months")
        #expect(PredictionText.ageLabel(ageDays: 425) == "13 months")
        #expect(PredictionText.ageLabel(ageDays: 800) == "2 years")
        #expect(PredictionText.ageLabel(ageDays: -3) == "newborns")
    }

    @Test func captionsNameTheBasis() {
        #expect(PredictionText.caption(basis: .typicalForAge, babyName: "Juniper", ageDays: 49) == "Typical for 7 weeks")
        #expect(PredictionText.caption(basis: .personal(days: 7), babyName: "Juniper", ageDays: 49) == "Based on Juniper's last 7 days")
        #expect(PredictionText.caption(basis: .blended(days: 5), babyName: "Juniper", ageDays: 49)
            == "Typical for 7 weeks, tuned to Juniper's last 5 days")
        #expect(PredictionText.caption(basis: .personal(days: 1), babyName: "Ada", ageDays: 49) == "Based on Ada's last day")
        #expect(PredictionText.caption(basis: .personal(days: 30), babyName: "Ada", ageDays: 49) == "Based on Ada's last 14 days", "never more than the 14 days used")
    }

    @Test func timingAgainstAWindow() {
        let start = TestSupport.utc(2026, 3, 1, 14, 10)
        let window = DateInterval(start: start, end: start.addingTimeInterval(30 * 60))
        #expect(PredictionText.timing(of: window, at: start.addingTimeInterval(-25 * 60)) == .upcoming(25 * 60))
        #expect(PredictionText.timing(of: window, at: start) == .now)
        #expect(PredictionText.timing(of: window, at: window.end) == .now)
        #expect(PredictionText.timing(of: window, at: window.end.addingTimeInterval(1)) == .overdue)
    }

    @Test func timingText() {
        #expect(PredictionText.Timing.upcoming(25 * 60).text == "in 25m")
        #expect(PredictionText.Timing.upcoming(24 * 60 + 10).text == "in 25m", "rounds up to the minute")
        #expect(PredictionText.Timing.upcoming(65 * 60).text == "in 1h 5m")
        #expect(PredictionText.Timing.upcoming(2 * 3600).text == "in 2h")
        #expect(PredictionText.Timing.upcoming(5).text == "in 1m")
        #expect(PredictionText.Timing.now.text == "now")
        #expect(PredictionText.Timing.overdue.text == "overdue")
    }

    @Test func disclaimerIsThePromisedSentence() {
        #expect(PredictionText.disclaimer == "Estimates from typical ranges and your logs. Not medical advice.")
        #expect(!PredictionText.howItWorks.isEmpty)
    }
}
