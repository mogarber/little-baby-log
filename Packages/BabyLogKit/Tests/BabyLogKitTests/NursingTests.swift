import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct NursingTests {
    let t0 = TestSupport.utc(2026, 3, 10, 8)

    @Test func startSwitchPauseFinish() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: t0, in: ctx)
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: t0, in: ctx)
        #expect(event.isRunning)

        event.startSide(.left, at: t0)
        #expect(event.activeSide == .left)
        #expect(event.lastSide == .left)
        #expect(event.breastSeconds(.left, at: t0.addingTimeInterval(120)) == 120)

        // Switch to right after 300s: left banks 300.
        event.startSide(.right, at: t0.addingTimeInterval(300))
        #expect(event.activeSide == .right)
        #expect(event.lastSide == .right)
        #expect(event.leftSeconds == 300)
        #expect(event.breastSeconds(.right, at: t0.addingTimeInterval(400)) == 100)
        #expect(event.totalBreastSeconds(at: t0.addingTimeInterval(400)) == 400)

        // Pause after another 200s on right.
        event.pauseNursing(at: t0.addingTimeInterval(500))
        #expect(event.activeSide == nil)
        #expect(event.rightSeconds == 200)
        #expect(event.totalBreastSeconds(at: t0.addingTimeInterval(9999)) == 500)
        #expect(event.isRunning, "paused nursing is still an open session")

        // Resume left, finish.
        event.toggleSide(.left, at: t0.addingTimeInterval(600))
        #expect(event.activeSide == .left)
        event.finishNursing(at: t0.addingTimeInterval(660))
        #expect(event.leftSeconds == 360)
        #expect(event.rightSeconds == 200)
        #expect(event.totalBreastSeconds(at: t0.addingTimeInterval(9999)) == 560)
        #expect(event.endDate == t0.addingTimeInterval(660))
        #expect(!event.isRunning)
        #expect(event.lastSide == .left)
        #expect(event.duration(at: t0.addingTimeInterval(9999)) == 560)
    }

    @Test func toggleActiveSidePauses() {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: t0, in: ctx)
        let event = LogEvent.create(kind: .breastfeed, for: baby, start: t0, in: ctx)
        event.toggleSide(.right, at: t0)
        event.toggleSide(.right, at: t0.addingTimeInterval(90))
        #expect(event.activeSide == nil)
        #expect(event.rightSeconds == 90)
        // Restarting the already-active side is a no-op.
        event.startSide(.left, at: t0.addingTimeInterval(100))
        event.startSide(.left, at: t0.addingTimeInterval(160))
        #expect(event.breastSeconds(.left, at: t0.addingTimeInterval(200)) == 100)
    }

    @Test func sideHelpers() {
        #expect(BreastSide.left.other == .right)
        #expect(BreastSide.right.other == .left)
        #expect(BreastSide.left.shortLabel == "L")
    }
}
