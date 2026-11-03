@preconcurrency import AppKit
@preconcurrency import EventKit
import FocusBreakCalendar
import FocusBreakCore
import FocusBreakUI
import SwiftUI

@main
struct FocusBreaksApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        MenuBarExtra("Focus Breaks", systemImage: "timer") {
            MenuBarContent(runtime: runtime)
                .task {
                    await runtime.model.send(.status)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
private final class AppRuntime {
    let model: MenuBarModel
    let preflight: DailyPreflightModel
    private(set) var pendingRecovery: SessionStateRecord?
    private(set) var recoveryError: String?

    private let commandSender: any SessionCommandSending
    private let server: CoordinatorSocketServer?
    private let coordinator: SessionCoordinator?
    private let stateStore: SessionStateStore?
    private var serverTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var reminderEngine = ReminderEngine()
    private var reminderEffects: ReminderEffectHandler?
    private var focusEndingWarnings: FocusEndingWarningController?
    private var screenMonitor: ScreenChangeMonitor?
    private var overlayActions: OverlayActionRelay?
    private var overlayController: OverlayController?
    private var preflightWindow = PreflightWindowController()
    private let completionDecision = SessionCompletionDecisionGate()

    init() {
        let paths: FocusBreakRuntimePaths
        do {
            paths = try FocusBreakRuntimePaths.userDefault()
        } catch {
            let unavailable = UnavailableCommandSender()
            commandSender = unavailable
            model = MenuBarModel(sender: unavailable)
            preflight = Self.makePreflight(sender: unavailable)
            server = nil
            coordinator = nil
            stateStore = nil
            return
        }

        let sender = CoordinatorCommandSender(socketURL: paths.socketURL)
        commandSender = sender
        model = MenuBarModel(sender: sender)
        preflight = Self.makePreflight(sender: sender)
        let stateStore = SessionStateStore(directory: paths.stateDirectory)
        self.stateStore = stateStore
        do {
            let server = try CoordinatorSocketServer(runtimeDirectory: paths.runtimeDirectory)
            let coordinator = SessionCoordinator(requiresDailyPlan: true)
            self.server = server
            self.coordinator = coordinator
            if let record = try? stateStore.load(for: Self.localDay()),
               ![.inactive, .completed].contains(record.coordinator.snapshot.phase) {
                pendingRecovery = record
            }
            serverTask = Task {
                while Task.isCancelled == false {
                    do {
                        try await server.serveOnce { request in
                            let response = try await coordinator.handle(request)
                            let state = await coordinator.exportState()
                            try stateStore.save(
                                SessionStateRecord(
                                    localDay: Self.localDay(),
                                    coordinator: state
                                )
                            )
                            return response
                        }
                    } catch {
                        if Task.isCancelled == false {
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }
                }
            }
        } catch {
            server = nil
            coordinator = nil
        }

        setUpReminderRuntime()
    }

    private func setUpReminderRuntime() {
        let actions = OverlayActionRelay()
        let environment = AppKitOverlayEnvironment(
            onComplete: { actions.complete() },
            onEmergencyDismiss: { actions.emergencyDismiss() },
            onStepAway: { actions.stepAway() },
            onStartAnotherSession: { actions.startAnotherSession() }
        )
        let overlays = OverlayController(environment: environment)
        let notifications = UserNotificationPoster()
        reminderEffects = ReminderEffectHandler(
            notifications: notifications,
            overlays: overlays
        )
        focusEndingWarnings = FocusEndingWarningController(poster: notifications)
        screenMonitor = ScreenChangeMonitor(controller: overlays)
        overlayActions = actions
        overlayController = overlays

        actions.onComplete = { [weak self] in
            Task { await self?.completeBreak() }
        }
        actions.onEmergencyDismiss = { [weak self] in
            Task { await self?.emergencyDismiss() }
        }
        actions.onStepAway = { [weak self] in
            self?.stepAwayAfterCompletion()
        }
        actions.onStartAnotherSession = { [weak self] in
            self?.startAnotherSessionAfterCompletion()
        }

        clockTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.tick(at: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick(at now: Date) async {
        guard pendingRecovery == nil else { return }
        do {
            var snapshot = try await commandSender.send(.status)

            if let command = SessionClock.dueCommand(for: snapshot, at: now) {
                let previous = snapshot
                snapshot = try await commandSender.send(command)
                await handleNaturalSessionCompletion(
                    from: previous,
                    to: snapshot,
                    after: command
                )
            }

            if snapshot.phase == .overlayActive,
               reminderEngine.isActive == false,
               let interval = snapshot.currentInterval,
               let kind = Self.reminderKind(for: interval.kind) {
                let effects = try reminderEngine.beginBreak(
                    kind,
                    duration: interval.duration,
                    at: now,
                    deadline: snapshot.deadline
                )
                try await handleReminderEffects(effects)
            }

            let escalation = reminderEngine.advance(to: now)
            if escalation.contains(where: Self.showsOverlay),
               snapshot.phase == .breakDue {
                snapshot = try await commandSender.send(.reminderEscalated)
            }
            try await handleReminderEffects(escalation)

            if [.inactive, .working, .completed].contains(snapshot.phase),
               reminderEngine.isActive {
                try await handleReminderEffects(reminderEngine.cancel())
            }

            model.apply(
                snapshot,
                remaining: SessionClock.remaining(for: snapshot, at: now)
            )
            await reconcileFocusEndingWarning(snapshot, at: now)
        } catch {
            // The menu model reports coordinator availability on the next explicit action.
        }
    }

    func resumeRecovery() async {
        guard let pendingRecovery, let coordinator else { return }
        do {
            try await coordinator.restore(pendingRecovery.coordinator)
            self.pendingRecovery = nil
            recoveryError = nil
            let snapshot = try await commandSender.send(.status)
            model.apply(
                snapshot,
                remaining: SessionClock.remaining(for: snapshot, at: Date())
            )
            await reconcileFocusEndingWarning(snapshot, at: Date())
        } catch {
            recoveryError = "The saved session could not be resumed."
        }
    }

    func discardRecovery() async {
        guard let pendingRecovery, let coordinator else { return }
        do {
            focusEndingWarnings?.cancel(for: pendingRecovery.coordinator.snapshot)
            let state = await coordinator.exportState()
            try stateStore?.save(
                SessionStateRecord(localDay: Self.localDay(), coordinator: state)
            )
            self.pendingRecovery = nil
            recoveryError = nil
            model.apply(await coordinator.snapshot)
        } catch {
            recoveryError = "The saved session could not be discarded."
        }
    }

    private func completeBreak() async {
        do {
            let previous = model.snapshot
            let snapshot = try await commandSender.send(.completeBreak)
            try await handleReminderEffects(reminderEngine.complete())
            await handleNaturalSessionCompletion(
                from: previous,
                to: snapshot,
                after: .completeBreak
            )
            model.apply(
                snapshot,
                remaining: SessionClock.remaining(for: snapshot, at: Date())
            )
            await reconcileFocusEndingWarning(snapshot, at: Date())
        } catch {
            await model.send(.status)
        }
    }

    private func emergencyDismiss() async {
        do {
            let previous = model.snapshot
            let effects = reminderEngine.emergencyDismiss(at: Date())
            let skipped = effects.contains(where: Self.skipsBreak)
            let snapshot = try await commandSender.send(skipped ? .skip : .snooze)
            try await handleReminderEffects(effects)
            if skipped {
                await handleNaturalSessionCompletion(
                    from: previous,
                    to: snapshot,
                    after: .skip
                )
            }
            model.apply(
                snapshot,
                remaining: SessionClock.remaining(for: snapshot, at: Date())
            )
            await reconcileFocusEndingWarning(snapshot, at: Date())
        } catch {
            await model.send(.status)
        }
    }

    private func handleNaturalSessionCompletion(
        from previous: SessionSnapshot,
        to current: SessionSnapshot,
        after command: SessionCommand
    ) async {
        guard SessionClock.didCompleteSchedule(
            from: previous,
            to: current,
            after: command
        ) else {
            return
        }
        do {
            try await handleReminderEffects([.sessionCompleteNotification])
        } catch {
            model.reportNotificationError(
                "The session-complete notification could not be delivered."
            )
        }
        showSessionCompletionPrompt()
    }

    private func showSessionCompletionPrompt() {
        guard completionDecision.begin() else { return }
        preflightWindow.close()
        overlayController?.show(SessionCompletionPresentation())
    }

    private func stepAwayAfterCompletion() {
        guard completionDecision.consume() else { return }
        overlayController?.hide()
        resetPreflight(at: Date())
    }

    private func startAnotherSessionAfterCompletion() {
        guard completionDecision.consume() else { return }
        overlayController?.hide()
        resetPreflight(at: Date())
        _ = preflightWindow.show(
            AnyView(
                DailyPreflightView(
                    model: model,
                    preflight: preflight,
                    onStarted: { [weak self] in self?.preflightWindow.close() }
                )
                .padding(20)
                .frame(minWidth: 380, minHeight: 420, alignment: .topLeading)
            )
        )
    }

    private func handleReminderEffects(_ effects: [ReminderEffect]) async throws {
        guard let reminderEffects else { return }
        for effect in effects {
            try await reminderEffects.handle(effect)
        }
    }

    private func reconcileFocusEndingWarning(
        _ snapshot: SessionSnapshot,
        at now: Date
    ) async {
        do {
            try await focusEndingWarnings?.reconcile(snapshot, at: now)
        } catch {
            model.reportNotificationError(
                "The five-minute focus warning could not be scheduled."
            )
        }
    }

    private static func reminderKind(
        for intervalKind: FocusInterval.Kind
    ) -> BreakReminderKind? {
        switch intervalKind {
        case .work: nil
        case .shortBreak: .shortBreak
        case .readingBreak: .readingBreak
        case .lunch: .lunch
        }
    }

    private static func showsOverlay(_ effect: ReminderEffect) -> Bool {
        if case .showOverlay = effect { return true }
        return false
    }

    private static func skipsBreak(_ effect: ReminderEffect) -> Bool {
        if case .skipped = effect { return true }
        return false
    }

    nonisolated private static func localDay() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func makePreflight(
        sender: any SessionCommandSending
    ) -> DailyPreflightModel {
        let now = Date()
        let defaults = preflightDefaults(at: now)
        let eventStore = EKEventStore()

        return DailyPreflightModel(
            sender: sender,
            calendar: CalendarCoordinator(
                source: EventKitCalendarSource(eventStore: eventStore)
            ),
            calendarWriteStore: EventKitCalendarWriteStore(eventStore: eventStore),
            notificationAuthorizer: UserNotificationPoster(),
            sessionStart: now,
            sessionEnd: defaults.sessionEnd,
            lunchStart: defaults.lunchStart,
            lunchEnd: defaults.lunchEnd,
            readingBreakMinutes: 30
        )
    }

    private func resetPreflight(at now: Date) {
        let defaults = Self.preflightDefaults(at: now)
        preflight.reset(
            sessionStart: now,
            sessionEnd: defaults.sessionEnd,
            lunchStart: defaults.lunchStart,
            lunchEnd: defaults.lunchEnd
        )
    }

    private struct PreflightDefaults {
        let sessionEnd: Date
        let lunchStart: Date
        let lunchEnd: Date
    }

    private static func preflightDefaults(at now: Date) -> PreflightDefaults {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let lunchStart = noon > now ? noon : now.addingTimeInterval(60 * 60)
        let lunchEnd = lunchStart.addingTimeInterval(90 * 60)
        let preferredEnd = calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: now
        ) ?? now.addingTimeInterval(8 * 60 * 60)
        return PreflightDefaults(
            sessionEnd: max(preferredEnd, lunchEnd.addingTimeInterval(2 * 60 * 60)),
            lunchStart: lunchStart,
            lunchEnd: lunchEnd
        )
    }
}

@MainActor
private final class OverlayActionRelay {
    var onComplete: (() -> Void)?
    var onEmergencyDismiss: (() -> Void)?
    var onStepAway: (() -> Void)?
    var onStartAnotherSession: (() -> Void)?

    func complete() {
        onComplete?()
    }

    func emergencyDismiss() {
        onEmergencyDismiss?()
    }

    func stepAway() {
        onStepAway?()
    }

    func startAnotherSession() {
        onStartAnotherSession?()
    }
}

@MainActor
private final class UnavailableCommandSender: SessionCommandSending {
    func send(_ command: SessionCommand) async throws -> SessionSnapshot {
        throw CoordinatorTransportError.systemCallFailed
    }

    func configure(_ plan: DailySessionPlan) async throws -> SessionSnapshot {
        throw CoordinatorTransportError.systemCallFailed
    }
}

private struct MenuBarContent: View {
    let runtime: AppRuntime

    private var model: MenuBarModel { runtime.model }
    private var preflight: DailyPreflightModel { runtime.preflight }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.statusTitle)
                    .font(.headline)
                Spacer()
                Text(model.remainingText)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .accessibilityLabel("Time remaining: \(model.remainingText)")
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }


            if model.snapshot.phase != .inactive,
               let warning = preflight.degradedWarning ?? preflight.calendarTargetWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Divider()

            if runtime.pendingRecovery != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A same-day focus session was found.", systemImage: "arrow.clockwise")
                    Text("Resume it or discard it before starting another session.")
                        .font(.caption)
                    if let recoveryError = runtime.recoveryError {
                        Text(recoveryError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Resume") {
                            Task { await runtime.resumeRecovery() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Discard") {
                            Task { await runtime.discardRecovery() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if model.snapshot.phase == .inactive || model.snapshot.phase == .completed {
                DailyPreflightView(model: model, preflight: preflight)
            } else {
                HStack {
                if model.canPause {
                    commandButton("Pause", systemImage: "pause.fill", command: .pause)
                }
                if model.canResume {
                    commandButton("Resume", systemImage: "play.fill", command: .resume)
                }
                if model.canSkip {
                    commandButton("Skip", systemImage: "forward.fill", command: .skip)
                }
                if model.canStop {
                    commandButton("Stop", systemImage: "stop.fill", command: .stop)
                }
                }
            }

            Divider()

            Button("Quit Focus Breaks") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func commandButton(
        _ title: String,
        systemImage: String,
        command: SessionCommand
    ) -> some View {
        Button {
            Task { await model.send(command) }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }
}

private struct DailyPreflightView: View {
    let model: MenuBarModel
    let preflight: DailyPreflightModel
    let onStarted: () -> Void

    init(
        model: MenuBarModel,
        preflight: DailyPreflightModel,
        onStarted: @escaping () -> Void = {}
    ) {
        self.model = model
        self.preflight = preflight
        self.onStarted = onStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily preflight")
                .font(.headline)

            DatePicker(
                "Session end",
                selection: Bindable(preflight).sessionEnd,
                displayedComponents: [.hourAndMinute]
            )
            if preflight.usesShortSessionDefaults {
                Label(
                    "Short session: one focus interval, with no scheduled breaks or calendar events.",
                    systemImage: "timer"
                )
                .font(.caption)
            } else {
                Toggle("Schedule lunch", isOn: Bindable(preflight).scheduleLunch)
                if preflight.scheduleLunch {
                    DatePicker(
                        "Lunch starts",
                        selection: Bindable(preflight).lunchStart,
                        displayedComponents: [.hourAndMinute]
                    )
                    DatePicker(
                        "Lunch window ends",
                        selection: Bindable(preflight).lunchEnd,
                        displayedComponents: [.hourAndMinute]
                    )
                }
                Stepper(
                    "Reading break: \(preflight.readingBreakMinutes) minutes",
                    value: Bindable(preflight).readingBreakMinutes,
                    in: 25...30
                )
            }

            Button("Generate preview") {
                Task {
                    preflight.sessionStart = Date()
                    await preflight.generatePreview(localDay: Self.localDay())
                }
            }
            .buttonStyle(.borderedProminent)

            if let warning = preflight.degradedWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let warning = preflight.notificationWarning {
                Label(warning, systemImage: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if preflight.availableTargetCalendars.count == 1,
               let calendar = preflight.availableTargetCalendars.first {
                Label(
                    "Calendar: \(calendar.sourceTitle) / \(calendar.title)",
                    systemImage: "calendar"
                )
                .font(.caption)
            } else if preflight.availableTargetCalendars.count > 1 {
                Picker(
                    "Calendar",
                    selection: Bindable(preflight).selectedCalendarIdentifier
                ) {
                    Text("Select a calendar").tag(String?.none)
                    ForEach(preflight.availableTargetCalendars, id: \.identifier) { calendar in
                        Text("\(calendar.sourceTitle) / \(calendar.title)")
                            .tag(Optional(calendar.identifier))
                    }
                }
            }

            if let warning = preflight.calendarTargetWarning {
                Label(warning, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = preflight.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let preview = preflight.preview {
                Divider()
                Text("Schedule preview")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(preview.intervals.enumerated()), id: \.offset) { _, interval in
                            HStack {
                                Text(Self.label(for: interval.kind))
                                Spacer()
                                Text("\(interval.start, format: .dateTime.hour().minute())–\(interval.end, format: .dateTime.hour().minute())")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)

                Text("Calendar proposal: reading and scheduled lunch only (\(preflight.calendarWrites.count) events).")
                    .font(.caption)

                Button("Confirm plan and start") {
                    Task {
                        do {
                            try await preflight.confirmAndStart()
                            await model.send(.status)
                            onStarted()
                        } catch {
                            await model.send(.status)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private static func localDay() -> String {
        Date.now.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
    }

    private static func label(for kind: FocusInterval.Kind) -> String {
        switch kind {
        case .work: "Focus"
        case .shortBreak: "Short break"
        case .readingBreak: "Reading"
        case .lunch: "Lunch"
        }
    }
}

@MainActor
private final class PreflightWindowController {
    private var windowController: NSWindowController?

    @discardableResult
    func show(_ rootView: AnyView) -> Bool {
        let hostingController = NSHostingController(rootView: rootView)
        if let window = windowController?.window {
            window.contentViewController = hostingController
            windowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return window.isVisible
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Start another work session"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 620))
        window.minSize = NSSize(width: 380, height: 420)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window.isVisible
    }

    func close() {
        windowController?.close()
    }
}
