import Testing
@testable import FocusBreakUI

@MainActor
struct SessionCompletionDecisionGateTests {
    @Test("only the first completion action is consumed")
    func consumesOnce() {
        let gate = SessionCompletionDecisionGate()

        #expect(gate.begin())
        #expect(gate.begin() == false)
        #expect(gate.consume())
        #expect(gate.consume() == false)
        #expect(gate.isActive == false)
    }

    @Test("cancel permits a later completion prompt")
    func cancels() {
        let gate = SessionCompletionDecisionGate()

        #expect(gate.begin())
        gate.cancel()
        #expect(gate.isActive == false)
        #expect(gate.begin())
    }
}
