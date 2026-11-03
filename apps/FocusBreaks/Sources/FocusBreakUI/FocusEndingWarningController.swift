import FocusBreakCore
import Foundation

@MainActor
public protocol FocusEndingWarningPosting: AnyObject {
    func scheduleFocusEndingWarning(_ warning: FocusEndingWarning) async throws
    func cancelFocusEndingWarning(identifier: String)
}

@MainActor
public final class FocusEndingWarningController {
    public private(set) var scheduledWarning: FocusEndingWarning?

    private let poster: any FocusEndingWarningPosting
    private var lastReconciledIdentifier: String?

    public init(poster: any FocusEndingWarningPosting) {
        self.poster = poster
    }

    public func reconcile(_ snapshot: SessionSnapshot, at now: Date) async throws {
        let desired = SessionClock.focusEndingWarning(for: snapshot, at: now)
        let currentIdentifier = SessionClock.focusEndingWarningIdentifier(for: snapshot)
        guard desired != scheduledWarning
                || currentIdentifier != lastReconciledIdentifier else {
            return
        }

        if let scheduledWarning {
            poster.cancelFocusEndingWarning(identifier: scheduledWarning.identifier)
        } else if desired == nil,
                  let identifier = currentIdentifier {
            poster.cancelFocusEndingWarning(identifier: identifier)
        }

        scheduledWarning = nil
        lastReconciledIdentifier = currentIdentifier
        if let desired {
            try await poster.scheduleFocusEndingWarning(desired)
            scheduledWarning = desired
        }
    }

    public func cancel(for snapshot: SessionSnapshot) {
        var identifiers = Set<String>()
        if let scheduledWarning {
            identifiers.insert(scheduledWarning.identifier)
        }
        if let identifier = SessionClock.focusEndingWarningIdentifier(for: snapshot) {
            identifiers.insert(identifier)
        }
        for identifier in identifiers {
            poster.cancelFocusEndingWarning(identifier: identifier)
        }
        scheduledWarning = nil
        lastReconciledIdentifier = nil
    }
}
