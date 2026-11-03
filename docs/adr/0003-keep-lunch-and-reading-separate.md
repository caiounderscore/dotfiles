# ADR-0003: Keep lunch and reading breaks separate

## Status

Accepted on 2026-07-20.

## Context

The cadence in [ADR-0001](0001-native-macos-focus-break-assistant.md) can make the protected
45-minute lunch and the 25–30-minute reading break due after the same work block. Combining
them would reduce the total pause but would make one interval serve two different recovery
goals.

## Decision

Lunch and reading remain separate first-class intervals. When both become due at the same
boundary, lunch occurs first and the complete reading break follows. The daily preview must
show the resulting 70–75-minute pause explicitly before confirmation.

## Alternatives considered

### Count reading as part of lunch

This avoids a long pause but weakens either protected meal time or protected reading time.

### Move reading to the next cycle

This shortens the immediate pause but breaks the rule that reading follows every two
completed work blocks.

## Consequences

- Both recovery goals retain their full duration.
- Some days include a long combined pause, visible before the user confirms the schedule.
- The planner and overlay state machine must preserve two consecutive interval identities.
