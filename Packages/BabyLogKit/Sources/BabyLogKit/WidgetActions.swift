import CoreData
import Foundation

/// One-tap actions for widgets, Live Activities, and App Intents. They mutate `context` but do not save;
/// the caller saves. Each takes the baby by uuid and returns `false` (changing nothing) when the baby, or
/// the timer being acted on, can't be found.
public enum WidgetActions {
    /// No running nursing → create one and start `side` (nil = the suggested next side, else left).
    /// Running → `toggleSide(side)`; with `side == nil` it pauses the active side, or resumes the last one.
    @discardableResult
    public static func nursing(
        babyID: UUID,
        side: BreastSide?,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> Bool {
        var done = false
        context.performAndWait {
            guard let baby = baby(id: babyID, in: context) else { return }
            if let running = runningEvent(.breastfeed, for: baby, in: context) {
                if let side {
                    running.toggleSide(side, at: now)
                } else if running.activeSide != nil {
                    running.pauseNursing(at: now)
                } else {
                    running.startSide(running.lastSide ?? .left, at: now)
                }
            } else {
                let suggested = (try? context.fetch(
                    LogEvent.requestLatest(baby: baby, kinds: [.breastfeed], finishedOnly: true)
                ))?.first?.lastSide?.other
                let event = LogEvent.create(kind: .breastfeed, for: baby, start: now, in: context)
                event.startSide(side ?? suggested ?? .left, at: now)
            }
            done = true
        }
        return done
    }

    /// Ends the running nursing session; deletes it instead when nothing was tracked (under a second).
    @discardableResult
    public static func finishNursing(babyID: UUID, in context: NSManagedObjectContext, now: Date = .now) -> Bool {
        var done = false
        context.performAndWait {
            guard let baby = baby(id: babyID, in: context),
                  let running = runningEvent(.breastfeed, for: baby, in: context) else { return }
            if running.totalBreastSeconds(at: now) < 1 {
                context.delete(running)
            } else {
                running.finishNursing(at: now)
            }
            done = true
        }
        return done
    }

    /// Running sleep → wake up (end it now). Otherwise start a sleep timer.
    @discardableResult
    public static func toggleSleep(babyID: UUID, in context: NSManagedObjectContext, now: Date = .now) -> Bool {
        var done = false
        context.performAndWait {
            guard let baby = baby(id: babyID, in: context) else { return }
            if let running = runningEvent(.sleep, for: baby, in: context) {
                running.endDate = max(now, running.startDate ?? now)
                running.modifiedAt = now
            } else {
                _ = LogEvent.create(kind: .sleep, for: baby, start: now, in: context)
            }
            done = true
        }
        return done
    }

    @discardableResult
    public static func logDiaper(
        babyID: UUID,
        kind: DiaperKind,
        in context: NSManagedObjectContext,
        now: Date = .now
    ) -> Bool {
        var done = false
        context.performAndWait {
            guard let baby = baby(id: babyID, in: context) else { return }
            let event = LogEvent.create(kind: .diaper, for: baby, start: now, in: context)
            event.diaperKind = kind
            done = true
        }
        return done
    }

    // MARK: Helpers

    private static func baby(id: UUID, in context: NSManagedObjectContext) -> Baby? {
        let request = Baby.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// The newest running timer of `kind`. Several can exist after two caregivers start one offline; act on the latest.
    private static func runningEvent(_ kind: EventKind, for baby: Baby, in context: NSManagedObjectContext) -> LogEvent? {
        ((try? context.fetch(LogEvent.requestRunning(baby: baby))) ?? []).first(where: { $0.kind == kind })
    }
}
