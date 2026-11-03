# ADR-0007: Make lunch optional and prompt after session completion

## Status

Accepted on 2026-07-21.

## Understanding summary

- Allow one macOS user to omit lunch from a new focus-session plan.
- Keep lunch enabled by default in each fresh preflight.
- Preserve short breaks and reading breaks when lunch is disabled.
- After natural session completion, cover every connected display with a decision prompt.
- Let the user step away or deliberately open a fresh preflight for another work session.
- Do not show the completion prompt after a manual Stop or start another session automatically.
- Reuse the native, local-only coordinator and multi-display overlay infrastructure.

## Context

The current daily preflight always asks for a lunch window, even when the user wants a work
session without lunch. The core schedule planner already accepts an absent lunch window, but
the preflight model always supplies one and the UI always displays lunch controls for regular
sessions.

When the final work interval completes, the application sends a notification and immediately
shows another preflight in its menu-bar popover. This does not create a strong boundary at the
end of the workday or ask the user to choose between leaving the desk and intentionally
planning more work.

## Assumptions and constraints

- Version 1 supports one macOS user and one global focus session across all clients.
- Lunch is a per-preflight choice, enabled by default; it is not a persistent preference.
- Disabling lunch does not disable short breaks or the reading break.
- Completion actions are advisory and accessible, not an enforced lock.
- Existing active-session recovery, calendar degraded mode, notification behavior, and break
  enforcement remain unchanged.
- The implementation uses only native macOS capabilities and repository-owned code.
- Overlay reconciliation and action handling remain responsive within the existing one-second
  runtime tick, and action callbacks are idempotent across displays.
- No new personal data, network integration, dependency, or persistence schema is introduced.

## Considered approaches

### Extend the existing preflight and overlay system — selected

Add lunch selection to the existing preflight model and generalize the existing overlay
presentation boundary so break and session-completion views share one multi-display window
lifecycle. Use a small native preflight window when the completion action requests another
session.

This is the smallest change that preserves global state, display reconciliation, and the
existing planner. It does require the overlay surface to render more than one presentation
type and a standalone preflight-window boundary.

### Add separate preflight and completion window controllers

Separate controllers isolate the views, but duplicate display tracking, window ordering,
action serialization, and lifecycle behavior.

### Model completion as a special break

This maximizes reuse of the current break presentation, but incorrectly gives an untimed,
optional decision the semantics of an enforced break and couples it to `ReminderEngine`.

## Decision

Add a `Schedule lunch` toggle to regular-session preflight, enabled by default. When disabled:

- hide the lunch start and end controls;
- pass `nil` as the planner's lunch window;
- omit lunch validation, intervals, reminders, and calendar writes;
- invalidate any preview generated with the previous toggle value.

Keep short-session behavior unchanged. Reading-break duration and scheduling remain independent
of lunch, consistent with ADR-0003.

Distinguish natural completion from a manual Stop. When the session clock naturally moves the
coordinator to `completed`, show a session-completion presentation through the existing overlay
controller on every connected display. A manual Stop ends the session without this prompt.

The prompt has two synchronized actions:

- **Step away** is the prominent and default action. It dismisses every overlay and leaves
  Focus Breaks running in the menu bar. Escape invokes the same action.
- **Start another work session** is secondary. It dismisses every overlay, clears completed
  preview and error state, derives new defaults from the current time, and opens a standalone
  native preflight window. It does not start a timer.

The first completion action received wins; callbacks from other display surfaces become
no-ops. Display connection changes reconcile through the existing screen monitor. If the
standalone preflight window cannot open, the reset preflight remains available in the menu-bar
UI. Quitting while the completion prompt is visible does not restore that prompt after
relaunch; active-session recovery remains unchanged.

## Acceptance checks

- Lunch is enabled by default in a fresh regular-session preflight.
- Disabling lunch hides its controls and produces a valid plan with no lunch interval,
  reminder, validation error, or calendar write.
- Changing the lunch toggle invalidates an existing preview.
- Reading and short breaks remain present according to their existing rules.
- Natural completion displays one synchronized prompt on every connected display.
- Manual Stop does not display the completion prompt.
- Display connection and removal reconcile the prompt without resetting its decision state.
- Concurrent actions from separate displays produce exactly one outcome.
- Step away dismisses all surfaces and keeps the menu-bar application running.
- Start another work session resets defaults, opens a fresh preflight, and starts no timer.
- Escape behaves like Step away.
- Preflight-window failure falls back to the fresh menu-bar preflight.
- Existing planner, break-overlay, notification, calendar, coordinator, and recovery tests
  remain green.

## Consequences

### Positive

- A session can match a day that does not need a lunch block.
- Natural completion creates an explicit health-oriented decision instead of silently
  continuing desk time.
- Reusing overlay lifecycle and coordinator state avoids competing global-session owners.
- The fallback preserves access to preflight even if native window presentation fails.

### Negative

- The overlay presentation boundary becomes more general than break-only rendering.
- A standalone preflight window adds lifecycle and focus behavior that needs UI-level tests.
- The lunch toggle is intentionally reset to enabled rather than remembered between sessions.

### Risks and mitigations

- Two displays may submit different actions nearly simultaneously. Serialize completion
  decisions and make later callbacks no-ops.
- A stale preview may retain lunch after the toggle changes. Invalidate preview and plan on
  every planning-input change.
- A completion overlay could be mistaken for enforced break UI. Use distinct copy, no timer,
  a default Step away action, and Escape support.

## Decision log

| Decision | Alternatives considered | Reason |
|---|---|---|
| Lunch is controlled by a default-on preflight toggle | Always required; default off; persistent preference | Preserves today's behavior while allowing an explicit exception. |
| Disabled lunch passes `nil` to the existing planner | Add a second planner mode | The core already represents optional lunch correctly. |
| Prompt only after natural completion | Also prompt after manual Stop | Manual Stop is already an explicit decision to end. |
| Cover every connected display | Primary display only | Matches the existing break boundary and prevents unnoticed continued work. |
| Step away dismisses overlays but keeps the app running | Quit; keep prompt visible | Leaves the tool available without trapping the user. |
| Start another opens a fresh preflight | Reuse old plan; start immediately | Requires deliberate planning and prevents accidental continued work. |
| Reuse one generalized overlay lifecycle | Separate controllers; special break | Minimizes duplicated display and action state without conflating semantics. |
| Do not restore the completion prompt after relaunch | Persist and restore it | The prompt is advisory; only active work needs recovery. |

## Related decisions

- [ADR-0001](0001-native-macos-focus-break-assistant.md): Native macOS focus and break assistant
- [ADR-0003](0003-keep-lunch-and-reading-separate.md): Keep lunch and reading breaks separate
- [ADR-0004](0004-allow-short-focus-sessions.md): Allow focus sessions shorter than the default block
- [ADR-0005](0005-enforce-full-break-duration.md): Enforce the full break duration before completion
