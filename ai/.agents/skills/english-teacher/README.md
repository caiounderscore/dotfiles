# english-teacher

A focused English coach/editor for Caio (Brazilian PT L1, Platform/SRE engineer) aiming for
natural, professional fluency. Companion to the always-on "English Notes" routine in the
shared personal instructions.

## What it does
- **Focused drills** on your recurring mistakes (spelling of cognates, dropped "to be",
  articles, prepositions, agreement, PT-literal phrasing).
- **Mock professional writing**: standups, PR descriptions, incident postmortems, ADRs, emails.
- **Immediate, categorized correction** with mini-drills.
- **Strict rising-bar scoring**: explicit deductions and hard caps account for first-time,
  logged, chronic, trivial/mechanical, and substantive errors.
- Shares one state file with the global English Notes:
  `~/.agents/state/language/english-mistakes-log.md`.

## How it differs from the always-on English Notes
- **English Notes** (shared instructions): passive — scores/corrects every message you write.
- **english-teacher**: active — deliberate practice sessions, drills, and mock writing on demand.
Both read and update the same log, so progress is consistent.

## Usage
Ask: "English drill on prepositions", "review my English mistakes", "let's do a mock PR
description", "score my writing".

## Files
- `SKILL.md` — role, modes, and correction protocol.
- `references/scoring-rubric.md` — authoritative deductions, caps, and repair rules.
- `references/recurring-patterns.md` — your error patterns, drills, professional-English snippets.
- `~/.agents/state/language/english-mistakes-log.md` — the shared recurring-errors log.
