# ADR-0006: Warn before each focus block ends

## Status

Accepted on 2026-07-21.

## Understanding summary

- Send one native macOS notification five minutes before every focus block ends.
- Use the standard notification sound and no repeated escalation.
- Apply the warning to regular and shortened focus blocks longer than five minutes.
- Recalculate the warning when pause and resume change the effective work deadline.
- Prevent duplicate notifications across coordinator refreshes and recovery.
- Preserve the existing explicit Resume or Discard recovery choice after an accidental quit.
- On Resume, recreate a still-future warning without sending a late notification.

## Context

Focus Breaks currently notifies when a break starts and when the session completes. It does
not warn that the current work block is about to end. A five-minute warning gives the user
time to finish the current thought and prepare to leave the desk instead of being interrupted
without notice by the enforced break overlay.

The application already persists the global session and offers Resume or Discard after a
same-day relaunch. The warning must follow that recovery flow without adding separate durable
state or producing duplicate notifications.

## Assumptions and constraints

- Version 1 supports one macOS user and one global focus session.
- Existing notification authorization and the native `UNUserNotificationCenter` are reused.
- The application remains local-only and introduces no dependency, calendar access, or
  additional personal data.
- Scheduling and cancellation should complete within the existing one-second runtime tick.
- macOS Focus mode or notification settings may suppress presentation even when scheduling
  succeeds.
- Break, reading, lunch, and daily-session boundaries do not receive this advance warning.

## Considered approaches

### Deterministic native scheduled notification — selected

Schedule a native notification when a work interval becomes active. Use a deterministic
identifier derived from the session ID and interval index, so reconciliation replaces the
same pending request rather than creating duplicates.

This continues to work while the application or display sleeps and requires no persistence
schema change. Pause, resume, transition, stop, and recovery require explicit reconciliation.

### Post from the existing one-second polling loop

This is initially smaller but can miss the threshold during sleep, needs an additional
deduplication flag, and can repeat after recovery.

### Persist a coordinator warning-delivered flag

This gives the coordinator explicit ownership but adds state-schema and migration complexity
that a deterministic native request identifier already avoids.

## Decision

Add a focus-ending notification operation to the native notification boundary. When a work
interval is active and its effective deadline is more than five minutes away, schedule one
notification for `deadline - 5 minutes` with:

- title: `Focus block ending soon`;
- body: `Five minutes remain. Finish your current thought and prepare for your break.`;
- the standard macOS notification sound;
- no actions, repetition, overlay, or calendar write.

The request identifier combines the session ID and current interval index. Scheduling the
same interval again replaces its existing pending request. Blocks whose total or remaining
duration is five minutes or less receive no advance notification.

Reconcile the pending notification after every snapshot change:

- starting or resuming a work interval schedules or replaces it;
- pausing cancels it;
- entering a break, stopping, or completing the session cancels it;
- ordinary status refreshes leave the deterministic request unchanged.

After relaunch, retain the existing Resume or Discard prompt. Discard cancels any known
pending request. Resume restores the coordinator snapshot and schedules the warning only if
its fire time is still in the future. It never emits a late catch-up notification.

Notification scheduling failure does not interrupt or modify the focus timer. The menu-bar
application reports the failure, while the existing preflight warning remains the primary
signal when notification permission is unavailable.

## Acceptance checks

- A 50-minute block schedules one warning at 45 minutes.
- A shortened block longer than five minutes schedules exactly five minutes before its
  effective deadline.
- A block lasting five minutes or less schedules no warning.
- Repeated reconciliation creates at most one pending request per interval.
- Pause cancels the request and Resume recreates it from the shifted deadline.
- Break entry, stop, completion, and Discard cancel the pending request.
- Resume before the warning boundary recreates it; Resume after the boundary does not send or
  schedule a late warning.
- Notification-center failure is visible but does not stop the local timer.

## Consequences

### Positive

- The user can wrap up deliberately before an enforced break.
- Native scheduling remains reliable through display and system sleep.
- Deterministic identifiers avoid another persisted state field and schema migration.
- Existing recovery behavior remains explicit and predictable.

### Negative

- Every work-state transition must reconcile a pending notification.
- Delivery cannot be guaranteed when macOS suppresses notifications.
- Notification failure and timer state must be reported separately.

## Decision log

| Decision | Alternatives considered | Reason |
|---|---|---|
| Warn before every focus block | Warn only before the daily session end; warn for both | The user selected each focus block. |
| Five-minute lead time | Ten minutes; daily configuration | The user selected five minutes. |
| One notification with sound | Silent; repeated | Provides notice without notification fatigue. |
| Native scheduled request | Polling-loop delivery; persisted coordinator flag | Survives sleep and deduplicates without schema changes. |
| Resume or Discard after relaunch | Automatic resume; preview-only recovery | Preserves explicit control and existing recovery semantics. |
| Skip late warnings during recovery | Immediate catch-up notification | Avoids stale, distracting alerts. |
