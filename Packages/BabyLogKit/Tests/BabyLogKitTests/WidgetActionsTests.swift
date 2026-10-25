import CoreData
import Testing
import Foundation
@testable import BabyLogKit

@MainActor
struct WidgetActionsTests {
    let t0 = TestSupport.utc(2026, 3, 10, 8)

    private func setUp() throws -> (NSManagedObjectContext, Baby, UUID) {
        let (_, ctx) = TestSupport.makeContext()
        let baby = Baby.create(name: "Ada", birthDate: t0, in: ctx)
        return (ctx, baby, try #require(baby.uuid))
    }

    private func running(_ kind: EventKind, _ baby: Baby, _ ctx: NSManagedObjectContext) throws -> [LogEvent] {
        try ctx.fetch(LogEvent.requestRunning(baby: baby)).filter { $0.kind == kind }
    }

    // MARK: nursing

    @Test func nursingStartsRequestedSide() throws {
        let (ctx, baby, id) = try setUp()
        #expect(WidgetActions.nursing(babyID: id, side: .right, in: ctx, now: t0))
        let event = try #require(try running(.breastfeed, baby, ctx).first)
        #expect(event.activeSide == .right)
        #expect(event.lastSide == .right)
        #expect(event.startDate == t0)
        #expect(event.baby == baby)
    }

    @Test func nursingWithoutSideUsesSuggestedNextSide() throws {
        let (ctx, baby, id) = try setUp()
        // Previous finished session ended on the left → suggest right.
        let previous = LogEvent.create(kind: .breastfeed, for: baby, start: t0.addingTimeInterval(-7200), in: ctx)
        previous.startSide(.left, at: previous.startDate!)
        previous.finishNursing(at: previous.startDate!.addingTimeInterval(600))

        #expect(WidgetActions.nursing(babyID: id, side: nil, in: ctx, now: t0))
        let event = try #require(try running(.breastfeed, baby, ctx).first)
        #expect(event.activeSide == .right)
    }

    @Test func nursingWithoutSideOrHistoryDefaultsLeft() throws {
        let (ctx, baby, id) = try setUp()
        WidgetActions.nursing(babyID: id, side: nil, in: ctx, now: t0)
        #expect(try running(.breastfeed, baby, ctx).first?.activeSide == .left)
    }

    @Test func nursingOnRunningTimerSwitchesAndPauses() throws {
        let (ctx, baby, id) = try setUp()
        WidgetActions.nursing(babyID: id, side: .left, in: ctx, now: t0)
        // Other side: left banks 120s.
        WidgetActions.nursing(babyID: id, side: .right, in: ctx, now: t0.addingTimeInterval(120))
        var events = try running(.breastfeed, baby, ctx)
        #expect(events.count == 1, "never starts a second timer")
        var event = events[0]
        #expect(event.activeSide == .right)
        #expect(event.leftSeconds == 120)
        // Same side again: pause.
        WidgetActions.nursing(babyID: id, side: .right, in: ctx, now: t0.addingTimeInterval(180))
        events = try running(.breastfeed, baby, ctx)
        event = events[0]
        #expect(event.activeSide == nil)
        #expect(event.rightSeconds == 60)
    }

    @Test func nursingNilSidePausesThenResumesLastSide() throws {
        let (ctx, baby, id) = try setUp()
        WidgetActions.nursing(babyID: id, side: .right, in: ctx, now: t0)
        WidgetActions.nursing(babyID: id, side: nil, in: ctx, now: t0.addingTimeInterval(60))
        var event = try #require(try running(.breastfeed, baby, ctx).first)
        #expect(event.activeSide == nil)
        #expect(event.rightSeconds == 60)
        WidgetActions.nursing(babyID: id, side: nil, in: ctx, now: t0.addingTimeInterval(100))
        event = try #require(try running(.breastfeed, baby, ctx).first)
        #expect(event.activeSide == .right, "resumes the last side")
        #expect(event.activeSideStartedAt == t0.addingTimeInterval(100))
    }

    @Test func finishNursingEndsOrDeletes() throws {
        let (ctx, baby, id) = try setUp()
        // Nothing running.
        #expect(!WidgetActions.finishNursing(babyID: id, in: ctx, now: t0))

        WidgetActions.nursing(babyID: id, side: .left, in: ctx, now: t0)
        #expect(WidgetActions.finishNursing(babyID: id, in: ctx, now: t0.addingTimeInterval(300)))
        #expect(try running(.breastfeed, baby, ctx).isEmpty)
        let all = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed]))
        #expect(all.count == 1)
        #expect(all[0].endDate == t0.addingTimeInterval(300))
        #expect(all[0].leftSeconds == 300)

        // Started and finished in the same instant → nothing tracked → deleted.
        WidgetActions.nursing(babyID: id, side: .right, in: ctx, now: t0.addingTimeInterval(1000))
        #expect(WidgetActions.finishNursing(babyID: id, in: ctx, now: t0.addingTimeInterval(1000)))
        try ctx.save()
        #expect(try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.breastfeed])).count == 1)
    }

    // MARK: sleep

    @Test func toggleSleepStartsAndEnds() throws {
        let (ctx, baby, id) = try setUp()
        #expect(WidgetActions.toggleSleep(babyID: id, in: ctx, now: t0))
        let sleep = try #require(try running(.sleep, baby, ctx).first)
        #expect(sleep.startDate == t0)
        #expect(sleep.endDate == nil)

        #expect(WidgetActions.toggleSleep(babyID: id, in: ctx, now: t0.addingTimeInterval(5400)))
        #expect(try running(.sleep, baby, ctx).isEmpty)
        #expect(sleep.endDate == t0.addingTimeInterval(5400))
        #expect(sleep.duration() == 5400)

        // And again → a new, separate sleep.
        WidgetActions.toggleSleep(babyID: id, in: ctx, now: t0.addingTimeInterval(9000))
        #expect(try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.sleep])).count == 2)
    }

    // MARK: diapers

    @Test func logDiaperCreatesInstantEvent() throws {
        let (ctx, baby, id) = try setUp()
        for kind in [DiaperKind.wet, .dirty, .mixed] {
            #expect(WidgetActions.logDiaper(babyID: id, kind: kind, in: ctx, now: t0))
        }
        let events = try ctx.fetch(LogEvent.requestAll(baby: baby, kinds: [.diaper]))
        #expect(Set(events.compactMap(\.diaperKind)) == [.wet, .dirty, .mixed])
        #expect(events.allSatisfy { $0.startDate == t0 && $0.endDate == nil && !$0.isRunning })
    }

    // MARK: unknown baby

    @Test func unknownBabyIsANoOp() throws {
        let (ctx, baby, _) = try setUp()
        let other = UUID()
        #expect(!WidgetActions.nursing(babyID: other, side: .left, in: ctx, now: t0))
        #expect(!WidgetActions.finishNursing(babyID: other, in: ctx, now: t0))
        #expect(!WidgetActions.toggleSleep(babyID: other, in: ctx, now: t0))
        #expect(!WidgetActions.logDiaper(babyID: other, kind: .wet, in: ctx, now: t0))
        #expect(try ctx.fetch(LogEvent.requestAll(baby: baby)).isEmpty)
    }

    @Test func actionsAreScopedToTheirBaby() throws {
        let (ctx, ada, adaID) = try setUp()
        let bo = Baby.create(name: "Bo", birthDate: t0, in: ctx)
        let boID = try #require(bo.uuid)
        WidgetActions.nursing(babyID: adaID, side: .left, in: ctx, now: t0)
        WidgetActions.toggleSleep(babyID: boID, in: ctx, now: t0)
        #expect(try running(.breastfeed, ada, ctx).count == 1)
        #expect(try running(.sleep, ada, ctx).isEmpty)
        #expect(try running(.breastfeed, bo, ctx).isEmpty)
        #expect(try running(.sleep, bo, ctx).count == 1)
        // Bo has no nursing to finish.
        #expect(!WidgetActions.finishNursing(babyID: boID, in: ctx, now: t0))
    }
}
