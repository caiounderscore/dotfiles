import Foundation
import Testing
@testable import FocusBreakCore

struct ReminderEngineTests {
    @Test("cancelling an active reminder hides any overlay without announcing completion")
    func cancelsReminder() throws {
        let now = Date(timeIntervalSince1970: 100)
        var engine = ReminderEngine()
        _ = try engine.beginBreak(.shortBreak, duration: 10 * 60, at: now)

        #expect(engine.cancel() == [.hideOverlay])
        #expect(engine.isActive == false)
    }

    private let now = Date(timeIntervalSince1970: 0)

    @Test("shows the overlay and notifies immediately")
    func startsBreakImmediately() throws {
        var engine = ReminderEngine()

        let initial = try engine.beginBreak(.shortBreak, duration: 10 * 60, at: now)
        #expect(initial.count == 2)
        #expect(initial[0].overlayModel?.kind == .shortBreak)
        #expect(initial[0].overlayModel?.deadline == now.addingTimeInterval(10 * 60))
        #expect(initial[1].notificationModel?.kind == .shortBreak)
        #expect(engine.advance(to: now.addingTimeInterval(60)).isEmpty)
    }

    @Test("first emergency dismissal snoozes for five minutes")
    func snoozesFirstDismissal() throws {
        var engine = ReminderEngine()
        _ = try engine.beginBreak(.readingBreak, duration: 30 * 60, at: now)

        #expect(engine.emergencyDismiss(at: now) == [.hideOverlay])
        #expect(engine.advance(to: now.addingTimeInterval(299)).isEmpty)
        #expect(
            engine.advance(to: now.addingTimeInterval(300)).first?.overlayModel?.kind
                == .readingBreak
        )
    }

    @Test("second emergency dismissal skips and records the break")
    func skipsSecondDismissal() throws {
        var engine = ReminderEngine()
        _ = try engine.beginBreak(.readingBreak, duration: 30 * 60, at: now)
        _ = engine.emergencyDismiss(at: now)
        _ = engine.advance(to: now.addingTimeInterval(300))

        #expect(engine.emergencyDismiss(at: now.addingTimeInterval(301)) == [
            .hideOverlay,
            .skipped(.readingBreak),
            .returnToWorkNotification,
        ])
        #expect(engine.isActive == false)
    }

    @Test("completion closes overlays and announces return to work")
    func completesBreak() throws {
        var engine = ReminderEngine()
        _ = try engine.beginBreak(.lunch, duration: 45 * 60, at: now)

        #expect(engine.complete() == [.hideOverlay, .returnToWorkNotification])
        #expect(engine.isActive == false)
    }

    @Test("presentation includes semantic guidance and accessible controls")
    func providesAccessiblePresentation() throws {
        var engine = ReminderEngine()

        let effects = try engine.beginBreak(.lunch, duration: 45 * 60, at: now)
        let model = try #require(effects.last?.notificationModel)

        #expect(model.title == "Lunch break")
        #expect(model.guidance.localizedCaseInsensitiveContains("eat"))
        #expect(model.completionLabel.isEmpty == false)
        #expect(model.emergencyDismissLabel.isEmpty == false)
        #expect(model.accessibilitySummary.isEmpty == false)
    }

    @Test("display reconciliation creates and removes exactly one surface per display")
    func reconcilesDisplays() {
        var registry = OverlayDisplayRegistry()

        let initial = registry.present(on: ["built-in", "external"])
        #expect(Set(initial.created) == ["built-in", "external"])
        #expect(initial.removed.isEmpty)

        let changed = registry.reconcile(with: ["external", "projector"])
        #expect(changed.created == ["projector"])
        #expect(changed.removed == ["built-in"])
        #expect(registry.activeDisplayIDs == ["external", "projector"])

        let dismissed = registry.dismiss()
        #expect(Set(dismissed.removed) == ["external", "projector"])
        #expect(registry.activeDisplayIDs.isEmpty)
    }
}

private extension ReminderEffect {
    var notificationModel: BreakPresentation? {
        guard case let .deliverNotification(model) = self else { return nil }
        return model
    }

    var overlayModel: BreakPresentation? {
        guard case let .showOverlay(model) = self else { return nil }
        return model
    }
}
