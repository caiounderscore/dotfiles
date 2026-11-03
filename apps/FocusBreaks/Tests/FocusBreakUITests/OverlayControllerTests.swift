import CoreGraphics
import FocusBreakCore
import Testing
@testable import FocusBreakUI

@MainActor
struct OverlayControllerTests {
    @Test("creates one surface per display and reconciles display changes")
    func reconcilesSurfaces() {
        let environment = FakeOverlayEnvironment(displays: [
            DisplayDescriptor(id: "built-in", frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            DisplayDescriptor(id: "external", frame: CGRect(x: 100, y: 0, width: 100, height: 100)),
        ])
        let controller = OverlayController(environment: environment)
        let presentation = fixturePresentation()

        controller.show(presentation)
        #expect(environment.surface(id: "built-in")?.presentCount == 1)
        #expect(environment.surface(id: "external")?.presentCount == 1)

        environment.displays = [
            DisplayDescriptor(id: "external", frame: CGRect(x: 0, y: 0, width: 200, height: 100)),
            DisplayDescriptor(id: "projector", frame: CGRect(x: 200, y: 0, width: 100, height: 100)),
        ]
        controller.reconcileDisplays()

        #expect(environment.surface(id: "built-in")?.dismissCount == 1)
        #expect(environment.surface(id: "external")?.updateCount == 1)
        #expect(environment.surface(id: "projector")?.presentCount == 1)
        #expect(controller.activeDisplayIDs == ["external", "projector"])
    }

    @Test("dismiss closes every active surface")
    func dismissesSurfaces() {
        let environment = FakeOverlayEnvironment(displays: [
            DisplayDescriptor(id: "built-in", frame: .zero),
            DisplayDescriptor(id: "external", frame: .zero),
        ])
        let controller = OverlayController(environment: environment)
        controller.show(fixturePresentation())

        controller.hide()

        #expect(environment.surfaces.values.allSatisfy { $0.dismissCount == 1 })
        #expect(controller.activeDisplayIDs.isEmpty)
    }

    @Test("session completion uses the same surfaces on every display")
    func presentsSessionCompletion() {
        let environment = FakeOverlayEnvironment(displays: [
            DisplayDescriptor(id: "built-in", frame: .zero),
            DisplayDescriptor(id: "external", frame: .zero),
        ])
        let controller = OverlayController(environment: environment)

        controller.show(SessionCompletionPresentation())

        #expect(environment.surface(id: "built-in")?.lastPresentation == .sessionCompletion(SessionCompletionPresentation()))
        #expect(environment.surface(id: "external")?.lastPresentation == .sessionCompletion(SessionCompletionPresentation()))
    }

    @Test("AppKit surface preserves the complete target display frame")
    func appKitSurfaceFillsDisplay() {
        let surface = AppKitOverlaySurface(
            displayID: "external",
            onComplete: {},
            onEmergencyDismiss: {}
        )
        let displayFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

        surface.update(.breakReminder(fixturePresentation()), frame: displayFrame)

        #expect(surface.windowFrame == displayFrame)
        surface.dismiss()
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
private final class FakeOverlayEnvironment: OverlayEnvironment {
    var displays: [DisplayDescriptor]
    private(set) var surfaces: [String: FakeOverlaySurface] = [:]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func makeSurface(for display: DisplayDescriptor) -> any OverlaySurface {
        let surface = FakeOverlaySurface(displayID: display.id)
        surfaces[display.id] = surface
        return surface
    }

    func surface(id: String) -> FakeOverlaySurface? {
        surfaces[id]
    }
}

@MainActor
private final class FakeOverlaySurface: OverlaySurface {
    let displayID: String
    private(set) var presentCount = 0
    private(set) var updateCount = 0
    private(set) var dismissCount = 0
    private(set) var lastPresentation: OverlayPresentation?

    init(displayID: String) {
        self.displayID = displayID
    }

    func present(_ presentation: OverlayPresentation, frame: CGRect) {
        presentCount += 1
        lastPresentation = presentation
    }

    func update(_ presentation: OverlayPresentation, frame: CGRect) {
        updateCount += 1
        lastPresentation = presentation
    }

    func dismiss() {
        dismissCount += 1
    }
}
