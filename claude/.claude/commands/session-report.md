---
description: Short end-of-session report on how to use Claude Code more effectively, plus session usage/billing
---

Review this entire conversation and produce a short, actionable report. Do not
write an essay — bullet points only, and only include a point if it's actually
grounded in something that happened in *this* session, not generic advice.

## 1. How I could use you better next time

Evaluate the session against these two lenses, and report only what's real:

**Context engineering** (was I feeding you the right information at the right
time?):
- Context starvation: did you have to guess at conventions, APIs, or file
  locations I could have just told you upfront?
- Context flooding: did I paste large irrelevant output/files when a smaller,
  targeted excerpt would have worked?
- Missing examples: did you invent a pattern/style because I didn't point you
  at an existing example to follow?
- Silent confusion: did you guess through an ambiguity instead of asking —
  because I didn't leave room for a question, or asked something too vague to
  clarify?
- Stale context: did this conversation run long enough that earlier decisions
  or file states drifted from what was actually true later on?

**Prompt construction** (were my requests structured well?):
- Which of my requests were vague/underspecified and cost back-and-forth to
  clarify, versus which were clear on the first try?
- For the vague ones: name the concrete framework that would have gotten it
  right in one pass (e.g. "Role-Task-Format", "give the constraint up front",
  "Chain of Thought for the debugging ask") — not framework jargon for its own
  sake, just the specific missing piece.

Output: 3-5 bullets max, each one concrete and tied to an actual moment in
this session (reference what was asked, not a hypothetical).

## 2. Session usage

Run `/usage` and report what it shows, plainly. Add this exact caveat
underneath: if I'm on a subscription plan (Pro/Max/Team), the cost figure
shown is not meaningful for billing — subscriptions have usage included, so
note that explicitly rather than presenting a dollar figure as a real charge.
If I'm on API/pay-as-you-go billing, present the estimated cost but note it's
a local estimate that may differ from the actual invoice (check the Claude
Console for authoritative billing).
