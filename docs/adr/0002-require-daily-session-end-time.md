# ADR-0002: Require a daily session end time

## Status

Accepted on 2026-07-20.

## Context

[ADR-0001](0001-native-macos-focus-break-assistant.md) requires the daily preview to show
all reading and lunch events before one calendar-write confirmation. It defines the session
start and lunch window but does not bound the end of the schedule. Without an end boundary,
the planner cannot determine the number of work blocks or approved reading events.

## Decision

The daily preflight will ask for the focus session's end time alongside the lunch window. The
end must be later than the session start and must leave enough time for at least one complete
50-minute work block. The preview will generate intervals only up to this boundary and will
not start an interval that would end after it.

If a busy-event deferral would push an approved reading break or lunch beyond the session
end, the preview will identify the conflict and require an explicit schedule adjustment. It
will not silently truncate or omit a protected break.

## Alternatives considered

### Fixed workday end

This would simplify planning but would not fit days with different schedules.

### Explicit number of work blocks

This provides a boundary but is less natural when the user plans around clock time, meetings,
and lunch.

### Generate reading events lazily

This avoids an end boundary but conflicts with the accepted one-confirmation-per-day calendar
write policy.

## Consequences

- The preview can enumerate every planned interval and calendar write deterministically.
- The user supplies one additional value at daily startup.
- Planner validation must cover short sessions and breaks that cross the end boundary.
- ADR-0001 remains authoritative for the rest of the assistant design; this ADR supplies its
  missing daily scheduling boundary.
