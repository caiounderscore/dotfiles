# ADR-0001: Native macOS focus and break assistant

## Status

Accepted on 2026-07-20.

## Understanding summary

- Build a personal macOS assistant that prevents prolonged, uninterrupted vibe-coding
  sessions and missed meals.
- Use a 50-minute work block followed by a 10-minute short break, with a 25–30-minute
  reading break after every two completed work blocks.
- Protect a configurable 45-minute lunch window with escalating reminders until the user
  acknowledges lunch.
- Coordinate every terminal, repository, and AI-agent client through one focus session for
  the current macOS user.
- Read only the calendar fields needed to identify busy intervals and write only approved
  reading and lunch events to a dedicated Fastmail calendar.
- Use native macOS capabilities and repository-owned code, with reversible overlays and
  explicit degraded behavior.
- Optimize for zero missed lunches and at least 80% break completion over a two-week trial.

## Context

Long coding sessions can displace hydration, movement, distance vision, reading, and lunch.
A normal notification is easy to ignore, while an irreversible screen lock could obstruct
urgent work. The assistant therefore needs adaptive escalation, calendar awareness, and a
prominent but reversible full-screen overlay.

The user runs multiple terminals and AI agents concurrently. Per-process timers would race,
duplicate reminders and calendar events, and disagree about whether a break was completed.
The focus session must consequently be a per-user singleton, independent of the initiating
terminal, AI client, or repository.

Fantastical is the calendar client and Fastmail is the backing account. EventKit can expose
calendar contents only through full read access; it does not offer a read-only authorization
level. The application must request the required platform permission while enforcing a
stricter internal data-minimization boundary.

## Decision drivers

- Reliable reminders without trapping the user during urgent work.
- One consistent session across concurrent terminal and AI-agent clients.
- Calendar-aware scheduling without retaining event content.
- No third-party runtime or Homebrew dependency.
- Local-first operation when calendar access or synchronization fails.
- Recoverable state transitions across process crashes, sleep, wake, and restarts.
- Accessibility on multiple displays.
- Minimal long-term behavioral data.

## Assumptions

- Version 1 supports one person and one macOS user account on one Mac.
- The user manually starts a daily session; activity monitoring and automatic startup are
  out of scope.
- The user creates exactly one writable Fastmail calendar named `Focus & Breaks`; the
  assistant never silently falls back to `Academic`, the Fantastical default, or another
  calendar.
- Reading-break duration is configurable from 25 through 30 minutes and is shown explicitly
  in the daily preview.
- The lunch window is chosen during the daily preview; lunch duration is 45 minutes.
- Calendar availability and synchronization are best effort. Local timers remain useful
  without them.
- All clients run as the same local macOS user. Cross-user and remote control are out of
  scope.

## Considered approaches

### 1. Native Swift menu-bar application and companion CLI — selected

The application owns scheduling, EventKit, notifications, overlays, and persistence. A
repository-owned `focusctl` client provides terminal and AI-agent control.

Advantages include reliable AppKit overlays, first-class accessibility, EventKit support,
native notifications, crash recovery, and no third-party runtime. The cost is a larger
implementation and macOS-specific code.

### 2. Native timer with Fantastical URL actions

This reduces EventKit write code and can open prefilled Fantastical events. It cannot provide
strong read-side calendar coordination or atomic, idempotent writes, and it delegates too
much correctness to UI automation and user interaction.

### 3. Shell and AppleScript automation

This is quick to prototype and fits a dotfiles repository. It is fragile across application
and macOS changes, provides weak multi-display and accessibility behavior, and makes
concurrency and crash recovery difficult. It was initially considered but rejected after
pressure-testing these failure modes.

## Decision

Implement a native Swift menu-bar application with a companion `focusctl` CLI. The
application is the sole coordinator for one per-user global focus session. Clients issue
commands through a local Unix-domain socket and never access the state store, EventKit, or
overlay windows directly.

### Components

- **SessionCoordinator**: authoritative state machine and serialized command handler.
- **SchedulePlanner**: creates the daily work, short-break, reading, lunch, and busy-deferral
  intervals.
- **CalendarGateway**: owns one `EKEventStore`, reduces events immediately to minimal busy
  intervals, and writes approved calendar events.
- **NotificationService**: emits native reminders and escalation notifications.
- **OverlayController**: maintains one reversible borderless window per active display.
- **StateStore**: atomically persists versioned, current-day recovery state under Application
  Support.
- **focusctl**: sends `start`, `status`, `pause`, `resume`, `snooze`, `skip`, and `stop`
  commands to the coordinator.

### Global-session coordination

The coordinator holds an exclusive per-user advisory lock. Its runtime directory is owned by
the user with mode `0700`; the socket is mode `0600`, and the coordinator verifies the peer
user ID. A second coordinator fails closed and reports the existing session instead of
creating another one.

Commands are serialized through the SessionCoordinator. Each mutating request carries a
unique request ID whose result is cached for the current day, so a retry cannot repeat a
transition or calendar write. Simultaneous `start` requests create one session; other clients
receive that session's status. Closing a client has no effect on the coordinator. Stale locks
and sockets are removed only after verifying that their owning process is absent.

Calendar events also have deterministic local identities linked to persisted EventKit event
identifiers. Ambiguous writes are never retried automatically. These controls guarantee one
timer, one overlay transition, and at most one intended calendar event even when several AI
agents issue commands concurrently.

### Daily planning and cadence

`focusctl start` launches or contacts the coordinator and begins one interactive preflight:

1. Check notification and calendar authorization and resolve exactly one writable
   `Focus & Breaks` calendar.
2. Ask for the day's lunch window.
3. Read only the required day range and immediately map calendar events to start time, end
   time, and busy/free status.
4. Generate a preview containing every 50-minute work block, 10-minute short break,
   25–30-minute reading break after every two completed work blocks, 45-minute lunch, and
   busy-event deferral.
5. Show the exact reading and lunch start times and durations, then request one confirmation
   for the day.
6. After confirmation, persist the pending plan before writing approved reading and lunch
   events. Focus blocks and short breaks remain local.

When a busy calendar event overlaps a break, the break becomes due immediately after the
event ends. The current work interval does not restart, and the deferred break is not counted
as missed.

### Reminders and overlays

When work ends, the coordinator enters `breakDue` and sends a native notification. If it is
not acknowledged within 60 seconds, the coordinator enters `overlayActive` and starts the
break timer. It creates one overlay on each display and reconciles windows when displays are
attached, removed, or rearranged.

The overlay shows the break type, remaining time, concise guidance, completion action, and a
visible emergency-dismiss control. Short-break guidance prioritizes hydration, movement, and
distance vision. Reading breaks use a low-distraction darkened presentation. Lunch remains
protected for 45 minutes and reminders escalate until acknowledged.

The first emergency dismissal snoozes the overlay for five minutes. A second dismissal skips
and records the break, then resumes work. The assistant does not invoke the macOS lock screen
or prevent emergency dismissal. On completion, overlays close and a return-to-work
notification appears. Controls support keyboard navigation, VoiceOver, reduced motion,
high-contrast presentation, and scalable text, with a target response latency below one
second.

### Calendar boundary and privacy

EventKit read access requires full calendar authorization, but the application enforces a
minimal internal contract: `BusyInterval(start, end, isBusy)`. It does not retain or log
titles, notes, attendees, locations, URLs, or raw EventKit objects. Reads use the smallest
needed current-day range.

Writes are restricted to the saved source identifier and calendar identifier for the unique,
writable `Focus & Breaks` calendar. The application also verifies the saved title and
writable state. A missing, duplicated, renamed, moved, or read-only target disables writes
and requires explicit reselection. It never falls back to another calendar.

If permission is denied or revoked, synchronization fails, or the calendar cannot be
resolved, local timers continue, writes are disabled, and a persistent degraded-mode warning
is displayed. Failure is never interpreted as an empty calendar.

### Persistence and recovery

State is a versioned JSON document in the application's Application Support directory. It is
written to a temporary file and atomically renamed. It contains the schema version, local
date, state-machine state, monotonic-relative and wall-clock recovery deadlines, planned
intervals, current-day completion counters, request IDs, EventKit event IDs, and selected
calendar/source IDs. It contains no event content.

Monotonic time drives active timers. Wall-clock deadlines exist only to reconstruct state
after restart. On a recent same-day recovery record, the application asks the user to Resume
or Discard and never resumes automatically. Sleep, wake, time-zone changes, and daylight
saving transitions trigger reconciliation before the next transition.

If a calendar write fails, subsequent writes stop and the application offers to remove any
events already created. If the process crashes after a write but before persisting the event
ID, that operation is marked ambiguous; the user must inspect the calendar before an explicit
reconciliation. The application does not retry the write automatically.

Current-day adaptive-enforcement history and aggregate metrics reset on the next local day.
No long-term behavior history is retained. Unified logs use privacy-redacted, stable fields.

## Testing and rollout

Use XCTest with injected monotonic and wall clocks plus protocol adapters around AppKit,
EventKit, notifications, persistence, and IPC. Keep state-machine tests independent of
framework UI types.

Required coverage includes:

- cadence, reading-break placement, lunch placement, and busy-event deferral;
- first snooze, second skip, completion, and lunch acknowledgement;
- simultaneous starts, conflicting commands, retry IDs, disconnected clients, stale sockets,
  coordinator crashes, and duplicate-write prevention;
- missing, duplicate, renamed, moved, or non-writable target calendars;
- denied or revoked permission, synchronization failure, and degraded mode;
- partial calendar writes and the ambiguous crash window;
- sleep, wake, time-zone changes, daylight saving transitions, and monotonic timing;
- Resume/Discard recovery, current-day reset, and state-schema migration;
- display attachment/removal and accessible overlay controls.

Roll out in independently reversible phases:

1. Schedule preview only.
2. Local notifications.
3. Multi-display overlays with calendar access disabled.
4. Calendar reads and busy deferral.
5. Calendar writes, enabled last.

Exercise each phase in real sessions before enabling the next. A dry run must show the exact
target calendar, start times, and durations. Rollback stops the coordinator and disables
future writes. Local state removal is explicit. Existing calendar events remain until the
user approves a cleanup preview.

## Success criteria

Evaluate the two-week trial using current-day aggregates only:

- zero missed lunches;
- at least 80% of scheduled breaks completed;
- reading-break frequency and maximum uninterrupted work duration reported as secondary
  signals;
- no duplicate overlays, timers, or calendar events under concurrent-client testing;
- degraded mode activates visibly whenever calendar correctness cannot be established.

## Explicit non-goals

- Linux or cross-platform support in version 1.
- Automatic activity monitoring or calendar-triggered session startup.
- OS-level screen locking.
- Reading or retaining calendar event content.
- Long-term behavioral tracking.
- Writing focus blocks or short breaks to a calendar.
- Cross-user, network, or remote coordination.

## Consequences

### Positive

- Native APIs provide dependable overlays, accessibility, notifications, and calendar access.
- One coordinator makes concurrent terminals and AI agents safe and predictable.
- The calendar boundary is explicit, minimal, and fail-closed for writes.
- Local timers remain available during calendar outages.
- Phased rollout allows each risky capability to be tested and disabled independently.

### Negative

- The solution is macOS-specific and requires Swift/AppKit/EventKit expertise.
- Reading busy times requires broad platform calendar permission despite narrow internal use.
- A coordinator, IPC protocol, idempotency ledger, and recovery state add complexity.
- The dedicated Fastmail calendar must be created and maintained by the user.
- Calendar write ambiguity can require manual inspection and reconciliation.

### Risks and mitigations

- **Overlay obstructs urgent work**: keep a visible emergency dismissal and never lock macOS.
- **Concurrent clients race**: enforce one coordinator, serialize transitions, and deduplicate
  request IDs.
- **Duplicate calendar events**: persist deterministic identities and never automatically
  retry ambiguous writes.
- **Calendar permissions expose excess data**: map events immediately to minimal busy
  intervals and prohibit content retention or logging.
- **Calendar outage hides meetings**: enter visible degraded mode rather than assuming the
  calendar is empty.
- **Crash corrupts state**: use atomic persistence, schema versions, and explicit recovery.
- **Reminder fatigue**: retain current-day adaptive escalation and measure completion during
  the trial.

## Decision log

| Decision | Alternatives considered | Reason |
|---|---|---|
| Native Swift menu-bar app plus `focusctl` | Fantastical URL actions; shell/AppleScript | Best reliability, accessibility, recovery, and native integration without third-party runtime dependencies. |
| One per-user global session | One timer per terminal, process, repository, or agent | Prevents races, duplicate timers, overlays, state, and calendar events. |
| Local socket plus exclusive coordinator lock | Direct shared-file mutation; independent processes | Provides serialized commands, peer validation, and one state-machine owner. |
| Adaptive notification then overlay | Notifications only; immediate hard lock | Makes breaks difficult to ignore while preserving an emergency path. |
| 50/10 cadence plus reading after two blocks | Standard 25/5; uniform breaks | Matches the preferred deep-work duration and reserves meaningful reading time. |
| Configurable 45-minute lunch window | Fixed lunch time; calendar-only lunch | Protects lunch while allowing daily schedule variation. |
| Hybrid calendar integration | Local-only; calendar-driven everything | Avoids meeting conflicts without making calendar availability a runtime dependency. |
| Read busy fields; write reading and lunch only | Read event content; write every interval | Minimizes data handling and calendar noise. |
| Dedicated Fastmail `Focus & Breaks` calendar | Use Fantastical default `Academic`; create local calendar | Separates assistant-owned events and prevents writes to an unrelated default calendar. |
| Continue locally in degraded mode | Stop the session; assume no events | Preserves reminders without hiding uncertainty or risking calendar writes. |
| Manual start and confirmation | Activity monitoring; automatic calendar start | Keeps version 1 explicit, private, and maintainable. |
| Current-day state and metrics only | Long-term analytics | Supports adaptation and success checks while minimizing behavioral data. |
| Resume/Discard after restart | Automatic resume; always discard | Avoids surprise overlays while preserving recoverability. |
| Phased rollout with writes last | Enable all capabilities together | Narrows failure domains and provides simple rollback. |

## References

- [Apple: Accessing the event store](https://developer.apple.com/documentation/EventKit/accessing-the-event-store)
- [Apple: EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [Apple WWDC23: Discover Calendar and EventKit](https://developer.apple.com/videos/play/wwdc2023/10052/)
- [Flexibits: Fantastical URL handler](https://flexibits.com/support/kb/51)
