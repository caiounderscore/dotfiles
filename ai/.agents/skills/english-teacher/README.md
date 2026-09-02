# english-teacher

An adaptive English coach and communication gate for Caio (Brazilian PT L1, Platform/SRE
engineer) aiming for natural, professional fluency. It is the active companion to the
always-on `English Notes` routine in the shared personal instructions.

## What it does
- **Per-message evaluation** of user-authored English before an underlying task is executed.
- **A hard communication gate** below 55, with preserved pending tasks and active repair.
- **Adaptive drills and sessions** with `/start-session`, `/end-session`, `/hard-mode`, and
  `/drill-mode`.
- **Pattern-level learning state** for immediate repair, spaced transfer tests, and spontaneous
  reuse.
- **Focused drills** on recurring mistakes (spelling, articles, prepositions, agreement,
  direct-question inversion, collocations, and PT-literal phrasing).
- **Mock professional writing**: standups, PR descriptions, incident postmortems, ADRs, emails.
- **Immediate, categorized correction** with mini-drills.
- **Strict, explainable scoring**: explicit severity, recurrence, confidence, and surface-
  protection rules distinguish new, recurring, and structural errors.
- Shares the durable human-readable state file with the global English Notes:
  `~/.agents/state/language/english-mistakes-log.md`.
- Structured machine-readable runtime state belongs outside Git at
  `~/.agents/state/language/english-training-state.yaml`.

## How it differs from the always-on English Notes

- **English Notes** (shared instructions): applies the compact score, correction, and gate to
  ordinary conversations.
- **english-teacher**: adds deliberate sessions, drills, mock writing, repair escalation, and
  transfer tracking on demand.

Both read and update the same durable log, so the gate and progress remain consistent.

## Usage
Ask: "English drill on prepositions", "review my English mistakes", "let's do a mock PR
description", "score my writing", or use `/start-session`.

## Files
- `SKILL.md` — role, modes, and correction protocol.
- `references/scoring-rubric.md` — authoritative deductions, scoring, and repair rules.
- `references/adaptive-training.md` — pending-task gate, repair escalation, transfer lifecycle,
  sessions, and metrics.
- `references/recurring-patterns.md` — your error patterns, drills, professional-English snippets.
- `~/.agents/state/language/english-mistakes-log.md` — the shared recurring-errors log.
