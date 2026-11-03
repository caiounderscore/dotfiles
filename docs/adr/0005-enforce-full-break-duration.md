# ADR-0005: Enforce the full break duration before completion

## Status

Accepted on 2026-07-21. Supersedes the reminder escalation, overlay timing, and break
completion portions of
[ADR-0001](0001-native-macos-focus-break-assistant.md). The remaining decisions in ADR-0001
continue to apply.

## Understanding summary

- Every scheduled short, reading, and lunch break opens a full-screen overlay immediately
  on every active display.
- `Complete break` remains disabled until the entire break duration has elapsed.
- Reaching zero does not start work automatically. The overlay remains until the user
  explicitly completes the break, and the next work block starts from that click time.
- The behavior is strong in-application friction, not an OS lock. `Emergency dismiss` and
  `Stop session` remain accessible escape paths.
- One coordinator enforces the same break for the menu-bar application, CLI, terminals, and
  AI-agent clients.

## Context

The initial implementation allowed a break to be marked complete before its timer expired.
That made it possible to dismiss the overlay after a few minutes and continue working during
the remainder of a scheduled break. ADR-0001 also delayed its overlay for 60 seconds after a
notification. Neither behavior provides the intended interruption to prolonged desk work.

The user may remain away after the timer reaches zero, so automatic advancement would record
work that has not actually resumed. Conversely, OS-level input interception or screen
locking would obstruct urgent use and exceed the privacy and reversibility boundaries of
ADR-0001.

## Decision drivers and constraints

- Prevent accidental early completion through every supported client.
- Do not start a work timer while the user remains away from the computer.
- Preserve a visible, accessible escape for urgent situations.
- Keep one authoritative session across concurrent clients.
- Recover conservatively after sleep, restart, clock changes, and partial failure.
- Use repository-owned Swift and native macOS capabilities only.
- Do not monitor user activity, intercept system input, or claim OS-level enforcement.

## Decision

### Coordinator-owned break state

`SessionCoordinator` is the sole authority for break eligibility. It samples an injected,
coordinator-owned clock while serializing each command; client-supplied timestamps never
determine whether a break may complete.

On break entry the coordinator records the break identity, type, duration, deadline,
dismissal count, and state revision. It requests persistence before producing notification
and overlay effects. All completion commands, including commands from `focusctl`, must carry
the expected break identity and revision. Request-ID idempotency handles retransmission; the
identity and revision precondition prevents two distinct concurrent requests from advancing
the state twice.

The deadline is inclusive: completion is accepted when coordinator time is greater than or
equal to the deadline. The UI displays the remaining duration rounded up, preventing `00:00`
from appearing while completion is still ineligible. An early completion attempt returns the
remaining duration rather than only an opaque error.

### Immediate overlay and explicit completion

Every scheduled short, reading, or lunch break immediately creates one native full-screen
overlay per active display. A single authoritative window owns keyboard focus and the
VoiceOver announcement; secondary display windows mirror the state without producing an
announcement storm. A native notification may be sent once, but it must not duplicate the
accessibility announcement. The previous 60-second notification-only grace period is
removed.

While time remains:

- `Complete break` is disabled and exposes an accessible explanation and remaining time.
- `Pause` is unavailable during the break.
- `Emergency dismiss` and `Stop session` remain keyboard- and VoiceOver-accessible.
- `Stop session` is clearly distinguished from completion and never receives default focus.

At the deadline, the overlay remains visible, `Complete break` becomes enabled, and the
primary message changes to: “Break complete — click Complete break when you are ready to
return.” No work block starts automatically. When the user explicitly completes the break,
the next work block is rebased from that completion time. Precomputed calendar events are
advisory estimates and never become runtime timing authority.

### Escape behavior

Escape behavior is tracked and persisted per break:

1. The first `Emergency dismiss` hides the overlay for five minutes. When that interval ends,
   the overlay returns and the full break duration restarts.
2. A second `Emergency dismiss` skips that break and advances according to the same explicit
   transition rules as other clients.
3. `Stop session` intentionally abandons the entire session.

The overlay explains these consequences before confirmation and reports the resulting state
afterward. This is strong in-app enforcement, not a claim that the application can prevent
force-quit, logout, or other OS-level escape.

### Time, persistence, and recovery

During one boot, monotonic system uptime drives the timer and includes system sleep. Wall
clock, time-zone, daylight-saving, and NTP changes cannot shorten the break.

Persistence stores the monotonic/uptime anchor, wall-clock anchor, recorded remaining
duration, break identity and revision, and dismissal state. After a reboot, when the prior
monotonic timeline cannot be proven, recovery is conservative and never reduces the recorded
remaining break. The UI explains any increased recovery duration. A recovered break that can
be proven expired displays zero and waits for explicit completion. An active break survives
midnight and is not discarded by the normal daily reset.

If persistence fails while entering or updating a break, the coordinator enters or retains
the enforced break in memory, forbids advancement to work, and shows a specific warning that
restart recovery is at risk. Persistence retries are idempotent and rate-limited. Corrupt or
incompatible state never silently resumes work; the user must explicitly discard the state
or stop the session.

Overlay reconciliation is also idempotent and rate-limited. It creates no duplicate windows,
adds an overlay for a newly attached display, and removes obsolete windows. A partial-display
failure leaves the coordinator in the break and displays a specific warning on available
surfaces; it does not report full enforcement success.

### Calendar and degraded modes

Calendar data remains advisory. Runtime transitions never use previously written event times
as session truth. When delayed completion shifts the actual schedule, the application labels
calendar times as estimates or stale coordination. Existing calendar write failures continue
to disable further writes while local timers remain active.

Persistence degradation and calendar degradation use different messages:

- persistence degradation states that the current break remains active but restart recovery
  may be unavailable;
- calendar degradation states that local timing remains authoritative, calendar times may be
  stale, and calendar writes are disabled.

## Alternatives considered

### Allow completion before zero with stronger warnings

This preserves maximum flexibility but reproduces the behavior that prompted the change: a
short acknowledgement can become uninterrupted work. It was rejected.

### Automatically begin work when the break timer reaches zero

This produces a predictable cadence but records work while the user may still be reading,
eating, or away. It was rejected in favor of explicit return.

### Enforce only in the overlay UI

This is smaller, but CLI or concurrent clients could complete the break early. It was
rejected because the existing architecture defines one global session.

### Lock macOS or intercept all input

This is stronger enforcement but is unsafe for urgent work, harder to make accessible, and
outside the accepted privacy boundary. It was rejected.

## Acceptance checks

- Exact-boundary tests cover one tick before the deadline, the inclusive deadline, and one
  tick after it without a visible `00:00` race.
- Short, reading, and lunch breaks reject early completion from the UI, CLI, and concurrent
  clients; duplicate and distinct simultaneous commands advance at most once.
- A late completion leaves the overlay active at zero and rebases the next work block from
  the explicit click time.
- Emergency-dismiss count and restarted duration survive relaunch; the second dismissal
  skips only the current break.
- Sleep counts toward a break; wall-clock changes cannot shorten it; reboot and midnight
  recovery never start work automatically.
- Persistence failure, corrupt state, overlay failure, and calendar divergence each produce
  their specified fail-closed or degraded behavior.
- Overlay creation and display hot-plugging are idempotent and do not create duplicate
  windows or repeated announcements.
- Keyboard-only and VoiceOver testing confirms predictable focus, one coherent transition
  announcement, and access to `Complete break`, `Emergency dismiss`, and `Stop session`.
- No test or production path relies on client timestamps, calendar events, user-activity
  monitoring, or input interception for enforcement.

## Consequences

### Positive

- A break cannot be accidentally completed early through a supported client.
- Work timing reflects the user's explicit return rather than an assumption at timer zero.
- Recovery and concurrent-client behavior remain deterministic and fail closed.
- Urgent escape and accessibility controls remain available.

### Negative

- The overlay is intentionally more disruptive and can remain indefinitely at zero.
- Conservative reboot recovery may extend a break when elapsed time cannot be proven.
- Calendar previews can diverge from actual timing after a delayed return.
- Clock abstraction, revision preconditions, failure states, and accessibility coordination
  add implementation and test complexity.

## Risks and mitigations

- **The feature is described as a computer freeze:** call it strong in-app enforcement and
  disclose the escape paths and force-quit limitation.
- **A stale or malicious client bypasses the timer:** use only coordinator-owned time and
  phase/revision preconditions.
- **A crash or failed write resumes work:** enter the break in memory, fail closed, retry
  persistence safely, and require explicit recovery decisions.
- **Multiple display windows overwhelm accessibility:** give one window announcement and
  focus authority while keeping controls accessible on every display.
- **The zero state appears hung:** change the message and enabled action explicitly at the
  deadline.
- **Calendar events become misleading:** label them advisory and surface stale coordination.

## Decision log

| Decision | Alternatives considered | Reason |
|---|---|---|
| Immediate overlay for every break | 60-second notification grace | Removes the easy continuation window at the start of a break. |
| Coordinator-enforced deadline | UI-only enforcement | Applies one rule to all terminals and AI-agent clients. |
| Explicit completion at zero | Automatic work start | The user may remain away longer than the minimum break. |
| Rebase work from completion time | Preserve the original absolute schedule | Avoids starting an expired or partially elapsed work block. |
| Per-break persisted emergency state | Process-local or daily dismissal count | Makes relaunch behavior predictable without removing the urgent escape. |
| Monotonic timing with conservative reboot recovery | Wall-clock-only deadline | Sleep counts while wall-clock adjustments cannot shorten the break. |
| Strong in-app enforcement | macOS lock or input interception | Preserves urgent access, accessibility, privacy, and reversibility. |
| Specific degraded states | One generic warning | Makes the operational consequence and recovery risk understandable. |

## Review record

The design received sequential Skeptic, Constraint Guardian, User Advocate, and
Integrator/Arbiter review. The first three reviewers requested revisions covering enforcement
terminology, delayed scheduling, clock trust, persistence failure, concurrency, escape
accessibility, zero-time messaging, and degraded-state clarity. Those objections are resolved
in this ADR. The Integrator/Arbiter disposition was **APPROVED** with no unresolved blockers.
