import FocusBreakCore
import Testing
@testable import FocusBreakUI

@MainActor
struct ReminderEffectHandlerTests {
    @Test("routes reminder effects to notifications and overlays")
    func routesEffects() async throws {
        let notifications = FakeNotificationPoster()
        let overlays = FakeOverlayController()
        let handler = ReminderEffectHandler(
            notifications: notifications,
            overlays: overlays
        )
        let presentation = fixturePresentation()

        try await handler.handle(.deliverNotification(presentation))
        try await handler.handle(.showOverlay(presentation))
        try await handler.handle(.hideOverlay)
        try await handler.handle(.returnToWorkNotification)
        try await handler.handle(.sessionCompleteNotification)
        try await handler.handle(.skipped(.readingBreak))

        #expect(notifications.breaks == [presentation])
        #expect(notifications.returnToWorkCount == 1)
        #expect(notifications.sessionCompleteCount == 1)
        #expect(overlays.shown == [presentation])
        #expect(overlays.hideCount == 1)
    }

    private func fixturePresentation() -> BreakPresentation {
        BreakPresentation(
            kind: .readingBreak,
            title: "Reading break",
            guidance: "Read your book.",
            duration: 30 * 60,
            completionLabel: "Complete break",
            emergencyDismissLabel: "Emergency dismiss",
            accessibilitySummary: "Reading break. Read your book."
        )
    }
}

@MainActor
private final class FakeNotificationPoster: NotificationPosting {
    private(set) var breaks: [BreakPresentation] = []
    private(set) var returnToWorkCount = 0
    private(set) var sessionCompleteCount = 0

    func postBreak(_ presentation: BreakPresentation) async throws {
        breaks.append(presentation)
    }

    func postReturnToWork() async throws {
        returnToWorkCount += 1
    }

    func postSessionComplete() async throws {
        sessionCompleteCount += 1
    }
}

@MainActor
private final class FakeOverlayController: OverlayControlling {
    private(set) var shown: [BreakPresentation] = []
    private(set) var hideCount = 0

    func show(_ presentation: BreakPresentation) {
        shown.append(presentation)
    }

    func hide() {
        hideCount += 1
    }
}
