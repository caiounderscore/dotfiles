import CoreGraphics
import FocusBreakCore

public struct SessionCompletionPresentation: Equatable, Sendable {
    public let title: String
    public let guidance: String
    public let stepAwayLabel: String
    public let startAnotherLabel: String
    public let accessibilitySummary: String

    public init(
        title: String = "Work session complete",
        guidance: String = "Step away from your desk, or deliberately plan another work session.",
        stepAwayLabel: String = "Step away",
        startAnotherLabel: String = "Start another work session",
        accessibilitySummary: String = "Work session complete. Choose whether to step away or plan another work session."
    ) {
        self.title = title
        self.guidance = guidance
        self.stepAwayLabel = stepAwayLabel
        self.startAnotherLabel = startAnotherLabel
        self.accessibilitySummary = accessibilitySummary
    }
}

public enum OverlayPresentation: Equatable, Sendable {
    case breakReminder(BreakPresentation)
    case sessionCompletion(SessionCompletionPresentation)
}

public struct DisplayDescriptor: Equatable, Sendable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

@MainActor
public protocol OverlaySurface: AnyObject {
    var displayID: String { get }

    func present(_ presentation: OverlayPresentation, frame: CGRect)
    func update(_ presentation: OverlayPresentation, frame: CGRect)
    func dismiss()
}

@MainActor
public protocol OverlayEnvironment: AnyObject {
    var displays: [DisplayDescriptor] { get }

    func makeSurface(for display: DisplayDescriptor) -> any OverlaySurface
}

@MainActor
public final class OverlayController {
    private let environment: any OverlayEnvironment
    private var presentation: OverlayPresentation?
    private var surfaces: [String: any OverlaySurface] = [:]

    public init(environment: any OverlayEnvironment) {
        self.environment = environment
    }

    public var activeDisplayIDs: [String] {
        surfaces.keys.sorted()
    }

    public func show(_ presentation: BreakPresentation) {
        show(.breakReminder(presentation))
    }

    public func show(_ presentation: SessionCompletionPresentation) {
        show(.sessionCompletion(presentation))
    }

    public func show(_ presentation: OverlayPresentation) {
        self.presentation = presentation
        reconcileDisplays()
    }

    public func reconcileDisplays() {
        guard let presentation else { return }

        let displays = Dictionary(
            uniqueKeysWithValues: environment.displays.map { ($0.id, $0) }
        )

        for displayID in surfaces.keys where displays[displayID] == nil {
            surfaces.removeValue(forKey: displayID)?.dismiss()
        }

        for (displayID, display) in displays {
            if let surface = surfaces[displayID] {
                surface.update(presentation, frame: display.frame)
            } else {
                let surface = environment.makeSurface(for: display)
                surfaces[displayID] = surface
                surface.present(presentation, frame: display.frame)
            }
        }
    }

    public func hide() {
        for surface in surfaces.values {
            surface.dismiss()
        }
        surfaces.removeAll()
        presentation = nil
    }
}
