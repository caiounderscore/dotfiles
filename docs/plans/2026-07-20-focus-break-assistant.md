# Focus Break Assistant Implementation Plan

This plan implements [ADR-0001](../adr/0001-native-macos-focus-break-assistant.md) and
[ADR-0002](../adr/0002-require-daily-session-end-time.md). Work proceeds in reviewable
batches. Each behavior follows red-green-refactor, and calendar writes remain disabled until
the final rollout phase.

## Constraints

- Swift tools 6.1 and macOS 14 minimum, matching the installed Swift 6.1.2 toolchain.
- Native Apple frameworks and repository-owned code only.
- Source lives under `apps/FocusBreaks`; runtime state remains under Application Support.
- One coordinator owns all mutable state. UI work is main-actor isolated; domain values are
  immutable and `Sendable`.
- Do not modify or stage unrelated dirty files.

## Batch 1: Scheduling foundation

### Task 1: Isolate and document

- Create branch `feat/macos-focus-breaks`.
- Record the missing end-time decision in ADR-0002.
- Add this implementation plan.
- Check: `git diff --check -- docs/adr docs/plans`.

### Task 2: Scaffold SwiftPM and establish RED

- Add `apps/FocusBreaks/Package.swift` with library `FocusBreakCore` and executable targets
  `FocusBreaks` and `focusctl`.
- Add schedule-planner tests for 50/10 cadence, reading after every second block, configurable
  reading duration, and the session-end boundary.
- Run the focused tests and confirm they fail for the missing planner behavior.

### Task 3: Implement the scheduling core

- Add immutable interval and configuration value types.
- Implement only the sequential cadence needed by the first tests.
- Validate duration ranges and prevent intervals from crossing the session end.
- Run `swift test` and `swift build`.

## Batch 2: Lunch and calendar-aware planning

### Task 4: Add lunch placement

- Test and implement one 45-minute lunch inside the selected window.
- Reject schedules that cannot fit lunch without truncation.
- Keep lunch a first-class interval.

### Task 5: Add busy-event deferral

- Test overlapping, adjacent, and chained busy intervals.
- Defer breaks until the busy interval ends without restarting the work interval.
- Mark a conflict when a protected break would pass the session end.

### Task 6: Add preview model

- Test exact start/end rendering inputs and the set of proposed calendar writes.
- Include reading and lunch writes only.

## Batch 3: Coordinator and IPC

### Task 7: Implement the session state machine

- Test legal and illegal transitions across inactive, work, break due, overlay, paused,
  completed, and degraded states.
- Inject monotonic and wall clocks.

### Task 8: Implement atomic persistence and recovery

- Test atomic saves, schema validation, current-day reset, and Resume/Discard recovery.
- Mark calendar writes ambiguous across the documented crash window.

### Task 9: Implement the per-user coordinator transport

- Test simultaneous starts, serialized conflicting commands, request-ID retries, stale
  sockets, and disconnected clients.
- Use a mode-`0700` runtime directory, mode-`0600` Unix socket, peer-UID validation, and one
  advisory lock.

## Batch 4: Native reminders and overlays

### Task 10: Add notification escalation

- Test notification, 60-second escalation, acknowledgement, and lunch escalation behavior.

### Task 11: Add accessible multi-display overlays

- Main-actor isolate AppKit window ownership.
- Test controller behavior with display adapters; manually verify keyboard, VoiceOver,
  reduced motion, contrast, and display reconciliation.
- Preserve the five-minute first dismissal and second-dismissal skip behavior.

### Task 12: Add the menu-bar status surface

- Expose current interval, remaining time, pause/resume, skip, and stop.
- Keep all mutations routed through the coordinator.

## Batch 5: EventKit integration

### Task 13: Add minimized calendar reads

- Request full EventKit access only when calendar coordination is enabled.
- Map events immediately to start, end, and busy status.
- Test denied/revoked permission, sync failure, and duplicate target calendars.

### Task 14: Add approved calendar writes

- Resolve only the saved writable Fastmail `Focus & Breaks` calendar.
- Test deterministic identities, partial writes, retry suppression, and explicit cleanup.
- Keep writes disabled by default until the rollout gate is enabled.

## Batch 6: Packaging and rollout

### Task 15: Package the menu-bar application

- Adapt the repository-owned packaging template for `FocusBreaks` and `focusctl`.
- Add the calendar usage description and explicit development entitlements.
- Validate the app bundle, binaries, and ad-hoc signature.

### Task 16: Exercise rollout phases

- Verify preview-only, notifications, overlays, calendar reads, then calendar writes.
- Record exact manual checks and rollback steps.
- Run full tests, build, package checks, and `git diff --check`.

## Completion checks

- `swift test --package-path apps/FocusBreaks`
- `swift build --package-path apps/FocusBreaks`
- package and inspect the `.app` bundle without launching it automatically
- `git diff --check`
- review the diff for credentials, event content, runtime state, and unrelated files
