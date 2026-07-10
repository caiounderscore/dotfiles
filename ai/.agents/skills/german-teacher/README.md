# german-teacher

A portable, expert German tutor tailored to one learner: A2+/early-B1, working through
**DaF kompakt neu A2 (Lektion 9–18)**, aiming for B1 (~mid-2027) then B2, with academic
plans in Germany.

## What it does
- **Book-first lessons** built on the DaF kompakt neu A2 unit themes and grammar.
- Structured sessions: **45 min weekdays** (warm-up → drill → output), **90 min Saturdays**
  (deeper, with reading + free production), or a **quick quiz**.
- **Test-prep mode**: cram schedules + timed mock tests that mirror the Übungsbuch exercise
  formats, for a Klassenarbeit/Prüfung on specific units.
- German-first instruction; English only when a concept is genuinely unclear.
- Immediate, categorized correction of every answer.
- Drills the learner's real weak points: Dativ/Akkusativ, article/adjective/possessive
  endings, word order, separable verbs, spelling, natural sentence-building.
- Tracks recurring mistakes in a portable neutral state file.

## Usage

Ask: "German lesson", "quiz me", "Saturday session", "prep me for a test on L9–L11",
"give me a mock test". The skill reads the neutral log when the client can access it.

## Other clients

The workflow is tool-agnostic. To use it in a client without skill discovery:

1. Paste `SKILL.md` (and, for a test, `references/test-prep-playbook.md` +
   `references/daf-kompakt-a2-map.md`) as custom instructions.
2. Paste the current neutral mistakes log.
3. Ask for a session and save the updated log it returns.

## Files
- `SKILL.md` — teacher instructions, modes, correction protocol, content priority.
- `references/daf-kompakt-a2-map.md` — Lektion 9–18 grammar/theme/exercise-type map.
- `references/test-prep-playbook.md` — cram schedules, mock-test blueprint, drill templates.
- `references/curriculum.md` — A2→B2 path, word banks, drill bank, quiz formats.
- `references/mistakes-log-template.md` — the portable error tracker.
- `~/.agents/state/language/german-mistakes-log.md` — the shared progress log.
