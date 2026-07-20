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
4. Correct both answers immediately: mark errors, give the natural form, name the category, explain briefly, and add one mini-drill per recurring category that appeared.
5. For the English answer and English log only, apply the strict rising bar in `../english-teacher/references/scoring-rubric.md`, including its deductions, caps, repair-evidence rules, and response gate. Always provide the warm-up correction; when the gate defers a non-urgent pending request, ask for a corrected English rewrite before continuing it.
6. Update the neutral logs only when authorized and writable.

If the sandbox blocks state writes, request narrowly scoped approval when appropriate. Otherwise return a copyable log update and continue without weakening sandbox or approval policy.
