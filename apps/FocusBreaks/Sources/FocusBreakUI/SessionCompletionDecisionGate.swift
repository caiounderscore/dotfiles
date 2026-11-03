@MainActor
public final class SessionCompletionDecisionGate {
    public private(set) var isActive = false

    public init() {}

    @discardableResult
    public func begin() -> Bool {
        guard isActive == false else { return false }
        isActive = true
        return true
    }

    @discardableResult
    public func consume() -> Bool {
        guard isActive else { return false }
        isActive = false
        return true
    }

    public func cancel() {
        isActive = false
    }
}
