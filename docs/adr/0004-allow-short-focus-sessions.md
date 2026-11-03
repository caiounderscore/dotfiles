# ADR-0004: Allow focus sessions shorter than the default block

## Status

Accepted on 2026-07-20. Supersedes the minimum-duration requirement in
[ADR-0002](0002-require-daily-session-end-time.md).

## Context

ADR-0002 requires every session to contain a complete 50-minute work block. That treats the
normal cadence as enforcement and prevents an intentional shorter session, such as finishing
a small task before a meeting. Lunch and reading configuration is not relevant when the
selected session cannot reach the first break.

## Decision

Fifty minutes remains the default work-block duration, not a minimum session duration. A
positive session lasting 50 minutes or less is planned as one work interval whose end exactly
matches the user-selected boundary. It has no short break, lunch interval, reading interval,
or calendar write. Lunch-window and reading-duration settings do not constrain this short
session path.

Sessions longer than 50 minutes continue to use the accepted 50/10 cadence and retain the
existing lunch, reading, calendar-preview, and calendar-confirmation rules. A session end that
is not later than its start remains invalid.

## Alternatives considered

### Keep a hard 50-minute minimum

This preserves a strict routine but blocks legitimate short focus periods and makes a default
behave like policy enforcement.

### Scale every break proportionally

This would preserve a work-to-rest ratio but adds configuration and unclear behavior for very
short sessions without providing meaningful recovery value.

### Add a separate short-session mode

An explicit mode would be clear but adds a control for behavior that can be inferred safely
from the selected end time.

## Consequences

- Users can end a focus session sooner without bypassing or abandoning the global session.
- Short sessions produce no protected-break or calendar side effects.
- The preflight hides irrelevant lunch and reading controls and labels the short-session plan.
- The standard behavior for longer sessions is unchanged.
