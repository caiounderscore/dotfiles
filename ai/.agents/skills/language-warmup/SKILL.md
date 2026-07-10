---
name: language-warmup
description: Run Caio's concise bilingual session warm-up with one German A2–B1 question and one English B2–C1 question, then correct both using neutral language-state logs. Use when explicitly requested or injected by a supported SessionStart adapter.
license: For personal use.
---

# Bilingual Language Warm-up

## State

- English: `~/.agents/state/language/english-mistakes-log.md`
- German: `~/.agents/state/language/german-mistakes-log.md`
- Unreconciled migrated German sources may exist under `~/.agents/state/language/migration-conflicts/`.

Read accessible state before choosing questions. If German conflict files exist without a canonical German log, use both as read-only context and do not silently merge their counts or histories.

## Workflow

1. Greet in one short line.
2. Ask exactly one German question at A2–B1 and exactly one English question at B2–C1. Prefer logged weak points and vary the prompts across sessions.
3. Wait for both answers before continuing the user's original request.
4. Correct both answers immediately: mark errors, give the natural form, name the category, explain briefly, and add one mini-drill for recurring errors.
5. Apply the rising bar: repeated logged errors receive an extra penalty and cap the score at 85; acknowledge repaired recurring errors.
6. Update the neutral logs only when authorized and writable.

If the sandbox blocks state writes, request narrowly scoped approval when appropriate. Otherwise return a copyable log update and continue without weakening sandbox or approval policy.
