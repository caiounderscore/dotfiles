# Focus Breaks

Focus Breaks is a native macOS menu-bar assistant and companion CLI for one per-user focus
session shared by every terminal and AI-agent process.

The standard cadence is 50 minutes of focus followed by a 10-minute break. Fifty minutes is
a default, not a minimum: selecting an earlier session end creates one shortened focus
interval and schedules no break, lunch, reading, or calendar event.

Every scheduled break opens its overlay immediately. `Complete break` remains disabled until
the timer reaches zero, and the overlay then waits for explicit completion before starting
the next work block. The first emergency dismissal snoozes and restarts the full break; only
the second emergency dismissal can skip it. If a completed break overruns into an adjacent
scheduled break, the time already spent away reduces or consumes that next break; focus time
is never shortened.

Work blocks longer than five minutes schedule one native notification with sound five minutes
before their effective deadline. Pause, resume, stop, interval transitions, and explicit
Resume or Discard recovery reconcile the deterministic pending notification without sending
late catch-up warnings.

Regular-session preflight schedules lunch by default, but the lunch toggle can omit its
window, reminders, and calendar write without removing reading or short breaks. Changing a
planning input invalidates the previous preview so stale schedules cannot be confirmed.

When the schedule ends naturally, a synchronized prompt covers every connected display.
`Step away` dismisses it while keeping Focus Breaks in the menu bar; `Start another work
session` opens a fresh preflight without starting a timer. Manual Stop does not show this
prompt.

## Current rollout state

The repository currently implements and tests the schedule planner, global coordinator and
socket transport, native reminders and overlays, menu controls, privacy-minimized EventKit
reads, guarded calendar writes, daily preflight, effective runtime deadlines, and explicit
Resume/Discard recovery. Calendar writes remain disabled until the user confirms the exact
daily preview and a writable Fastmail `Focus & Breaks` calendar. Real notification,
multi-display, sleep/wake, and calendar-sync behavior still require manual rollout checks
before relying on the app for real sessions.

## Build and test

```sh
swift test --package-path apps/FocusBreaks
swift build --package-path apps/FocusBreaks
```

## Package without launching

```sh
bash apps/FocusBreaks/scripts/package.sh
```

The script creates `apps/FocusBreaks/.build/FocusBreaks.app`, embeds `focusctl` under
`Contents/Helpers`, applies an ad-hoc signature, and verifies the bundle. It does not install
or launch the application.

## Safety boundary

- The coordinator socket and lock are private to the current macOS user.
- Calendar reads retain only event start, end, and busy status.
- Calendar writes require a same-day confirmation and the saved writable Fastmail
  `Focus & Breaks` identifier. No name-based fallback is allowed.
- Calendar failure keeps local timers enabled, disables writes, and requires a visible
  degraded-mode warning.
