@preconcurrency import AppKit
import FocusBreakCore
import SwiftUI

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
public final class AppKitOverlayEnvironment: OverlayEnvironment {
    private let onComplete: () -> Void
    private let onEmergencyDismiss: () -> Void
    private let onStepAway: () -> Void
    private let onStartAnotherSession: () -> Void

    public init(
        onComplete: @escaping () -> Void,
        onEmergencyDismiss: @escaping () -> Void,
        onStepAway: @escaping () -> Void = {},
        onStartAnotherSession: @escaping () -> Void = {}
    ) {
        self.onComplete = onComplete
        self.onEmergencyDismiss = onEmergencyDismiss
        self.onStepAway = onStepAway
        self.onStartAnotherSession = onStartAnotherSession
    }

    public var displays: [DisplayDescriptor] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
            let fallbackID = String(ObjectIdentifier(screen).hashValue)
            return DisplayDescriptor(id: number?.stringValue ?? fallbackID, frame: screen.frame)
        }
    }

    public func makeSurface(for display: DisplayDescriptor) -> any OverlaySurface {
        AppKitOverlaySurface(
            displayID: display.id,
            onComplete: onComplete,
            onEmergencyDismiss: onEmergencyDismiss,
            onStepAway: onStepAway,
            onStartAnotherSession: onStartAnotherSession
        )
    }
}

@MainActor
public final class ScreenChangeMonitor {
    private var token: NSObjectProtocol?

    public init(controller: OverlayController) {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                controller.reconcileDisplays()
            }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
final class AppKitOverlaySurface: OverlaySurface {
    let displayID: String

    private let window: NSWindow
    private let onComplete: () -> Void
    private let onEmergencyDismiss: () -> Void
    private let onStepAway: () -> Void
    private let onStartAnotherSession: () -> Void

    var windowFrame: CGRect { window.frame }

    init(
        displayID: String,
        onComplete: @escaping () -> Void,
        onEmergencyDismiss: @escaping () -> Void,
        onStepAway: @escaping () -> Void = {},
        onStartAnotherSession: @escaping () -> Void = {}
    ) {
        self.displayID = displayID
        self.onComplete = onComplete
        self.onEmergencyDismiss = onEmergencyDismiss
        self.onStepAway = onStepAway
        self.onStartAnotherSession = onStartAnotherSession
        window = OverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = true
        window.level = .screenSaver
        window.hasShadow = false
    }

    func present(_ presentation: OverlayPresentation, frame: CGRect) {
        update(presentation, frame: frame)
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(_ presentation: OverlayPresentation, frame: CGRect) {
        let hostingView = NSHostingView(
            rootView: OverlayRootView(
                presentation: presentation,
                onComplete: onComplete,
                onEmergencyDismiss: onEmergencyDismiss,
                onStepAway: onStepAway,
                onStartAnotherSession: onStartAnotherSession
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setFrame(frame, display: true)
    }

    func dismiss() {
        window.orderOut(nil)
    }
}

private struct OverlayRootView: View {
    let presentation: OverlayPresentation
    let onComplete: () -> Void
    let onEmergencyDismiss: () -> Void
    let onStepAway: () -> Void
    let onStartAnotherSession: () -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case let .breakReminder(breakPresentation):
            BreakOverlayView(
                presentation: breakPresentation,
                onComplete: onComplete,
                onEmergencyDismiss: onEmergencyDismiss
            )
        case let .sessionCompletion(completionPresentation):
            SessionCompletionOverlayView(
                presentation: completionPresentation,
                onStepAway: onStepAway,
                onStartAnotherSession: onStartAnotherSession
            )
        }
    }
}

private struct BreakOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let presentation: BreakPresentation
    let onComplete: () -> Void
    let onEmergencyDismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(presentation.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remainingSeconds = remainingSeconds(at: context.date)
                let remaining = remainingText(seconds: remainingSeconds)

                VStack(spacing: 28) {
                    Text(
                        remainingSeconds == 0
                            ? "Break complete — click Complete break when you are ready to return."
                            : presentation.guidance
                    )
                    .font(.title2)
                    .multilineTextAlignment(.center)

                    Text(remaining)
                    .font(.system(.title, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("Break time remaining: \(remaining)")

                    HStack(spacing: 20) {
                        Button(presentation.completionLabel, action: onComplete)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(remainingSeconds > 0)
                            .accessibilityHint(
                                remainingSeconds > 0
                                    ? "Available when the break timer reaches zero."
                                    : "Starts the next focus block."
                            )

                        Button(presentation.emergencyDismissLabel, action: onEmergencyDismiss)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .keyboardShortcut(.cancelAction)
                            .accessibilityHint(
                                "The first dismissal hides this break for five minutes and restarts it; the second skips it."
                            )
                    }
                }
            }
        }
        .padding(64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(backgroundColor.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: presentation.kind)
    }

    private func remainingSeconds(at now: Date) -> Int {
        presentation.deadline.map {
            max(0, Int($0.timeIntervalSince(now).rounded(.up)))
        } ?? Int(presentation.duration)
    }

    private func remainingText(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var backgroundColor: Color {
        contrast == .increased ? .black : Color(red: 0.04, green: 0.07, blue: 0.12)
    }
}

private struct SessionCompletionOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let presentation: SessionCompletionPresentation
    let onStepAway: () -> Void
    let onStartAnotherSession: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(presentation.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))

            Text(presentation.guidance)
                .font(.title2)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                Button(presentation.stepAwayLabel, action: onStepAway)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Closes this prompt and keeps Focus Breaks in the menu bar.")

                Button(presentation.startAnotherLabel, action: onStartAnotherSession)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Opens a fresh preflight without starting a timer.")
            }
        }
        .padding(64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(backgroundColor.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: presentation)
    }

    private var backgroundColor: Color {
        contrast == .increased ? .black : Color(red: 0.04, green: 0.07, blue: 0.12)
    }
}
