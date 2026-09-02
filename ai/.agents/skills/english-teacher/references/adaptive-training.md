# Adaptive training mechanics

This reference defines the stateful behavior layered on top of the scoring rubric. It is
deliberately implementation-neutral: the assistant maintains the state in the conversation and
persists it under the neutral language-state directory when writable.

## State model

Use the durable log for human-readable evidence and initialize this structured runtime state at
`~/.agents/state/language/english-training-state.yaml` when it is absent:

```yaml
english_session:
  current_score: 0
  blocked: false
  pending_task: null
  blocking_reason: []
  current_targets: []
  active_patterns: []
  repaired_patterns: []
  transfer_pending: []
  spontaneous_successes: []
  repair_attempts: 0
  turn: 0
  mode: normal

english_profile:
  canonical_categories: {}
  patterns: {}
  historical_examples: []
  repair_history: []
  mastery_history: []
  metrics:
    spontaneous_correct_reuse_rate: 0
    recurring_error_rate: 0
    repair_success_rate: 0
    transfer_success_rate: 0
    average_unassisted_score: 0
    blocked_message_rate: 0
```

Pattern entries should retain both frequency and learning evidence:

```yaml
patterns:
  direct_question_inversion:
    category: verb_forms_and_agreement
    errors: 12
    repairs: 8
    spontaneous_successes: 3
    open_recurrence_priority: 4
    status: transfer_pending
    last_error_turn: 41
    next_transfer_turn: 45
    recent_error_turns: [38, 41]
```

Valid pattern statuses are `active`, `repaired`, `transfer_pending`, `improving`, and
`stable`. `errors` is lifetime evidence and does not decrease. An immediate successful repair
decrements the current category priority under the existing repair convention; a later
spontaneous transfer success decrements `open_recurrence_priority`. Do not use lifetime history
as the current score or as unlimited punishment.

## Evaluation order

For every intentionally English message:

```text
prose = extractAssessableEnglish(message)
if prose is empty:
    handle command or task normally

evaluation = evaluate(prose, log, profile)
updateErrorAndPositiveEvidence(evaluation)

if evaluation.score < 55 and no protective exception:
    if session.pending_task is null:
        session.pending_task = preserveOriginalTask(message)
        session.blocked = true
        session.blocking_reason = evaluation.deductions
    else:
        treat message as a repair attempt
    return repairResponse(evaluation)

if session.blocked:
    recordImmediateRepairs(evaluation)
    pending = session.pending_task
    clearBlockedSession()  # also reset blocking_reason and repair_attempts
    return briefFeedback(evaluation) + continue(pending)

return handleTask(message) + compactEnglishNotes(evaluation)
```

`preserveOriginalTask` stores the original request and enough surrounding context to resume it;
`blocking_reason` stores the visible deduction list so every block is explainable:

```yaml
pending_task:
  original_request: "..."
  blocked_at_score: 48
  status: waiting_for_language_repair
blocking_reason:
  - pattern: direct_question_inversion
    deduction: -14
  - pattern: fixed_prepositions
    deduction: -12
```

Do not replace this object with a retry. A retry is language evidence, not a new technical
request, unless the user clearly changes the task. Once a passing retry clears the gate, execute
the original request without asking the user to repeat its context.

The boundary is exact: a final score of `54` blocks the task; a corrected retry scoring `55`
passes the gate and resumes the preserved task.

## Repair interaction

The blocked response has this shape:

```text
🔒 English gate: XX/100
Minimum required: 55

Main issues:
1. 🔁 ...
2. 🔁 ...
3. 🆕 ...

Rewrite your request before we continue.
Focus on: ...
```

Choose no more than three targets by pedagogical value: prefer serious structural errors,
recurring patterns, and errors that affect meaning. Give the natural form as evidence when
useful, but normally withhold the complete final request so the user must reconstruct it.

Escalate hints without creating an infinite loop:

| Failed repair count | Response |
|---:|---|
| 1 | normal hints and a short explanation |
| 2 | stronger hints and identify the relevant sentence structure |
| 3 or more | a partially completed sentence with blanks |

For the third level, use a useful frame such as:

```text
Let's ______ these values instead of using ______ variables.
```

Do not lower the threshold automatically. The user always has a concrete path to `55` or
higher, and the original task remains untouched until then.

On a passing repair, record:

```yaml
repair_event:
  category: verb_forms_and_agreement
  pattern: modal_plus_base
  status: repaired
  evidence: "The user supplied a corrected rewrite."
```

Then move the pattern to `transfer_pending`. Immediate repair is useful but is not mastery.

## Transfer and spacing

Schedule the first hidden transfer test roughly 3–7 conversational turns after repair, then a
later-session test. Do not announce the grammar target. Ask for a natural response in a new
situation, for example:

```text
Imagine a teammate deployed a new authentication service. Ask me whether authentication is
mandatory for internal requests.
```

Record a later spontaneous correct use separately from the immediate repair:

```yaml
positive_evidence:
  pattern: direct_question_inversion
  type: spontaneous
  context: "A general-life question, not the original repair sentence."
```

After multiple spaced spontaneous successes, transition `transfer_pending` → `improving` →
`stable`. A correct sentence that merely avoids a target, copies the correction, or is too short
to test it does not count. Do not repeatedly reuse historical corrected sentences; vary domain,
syntax, and communicative purpose.

## Session modes

### `/start-session`

Inspect the log and profile, select two highest-priority active or transfer-pending patterns,
and optionally one secondary pattern. Consider frequency, recency, severity, repair success, and
transfer due—not only the largest lifetime count. Do not reveal the complete target list.

Use approximately 60–70% technical/professional contexts (Kubernetes, SRE, cloud, architecture,
debugging, meetings, incidents, planning, and code review) and 30–40% general-life contexts
(travel, university, daily life, opinions, preferences, and plans). General contexts are
required for transfer beyond memorized technical phrasing.

### `/end-session`

Return no more than three items in each problem/improvement group:

```text
English session: 78/100

Strongest improvements
1. ...

Still active
1. ...

Spontaneous repairs
- ...

Patterns requiring transfer testing
- ...

Next session
1. ...
```

Use measured evidence from the session. Do not dump the complete history.

### `/hard-mode`

Keep the threshold at `55`. Use fewer hints, avoid naming the exact grammar rule before a repair,
ask for longer responses and more spontaneous questions, and introduce hidden transfer situations
more often.

### `/drill-mode`

Select one pattern, present one prompt, evaluate the answer, ask for a retry when needed, then
give a variation and later transfer test. Do not ask multiple questions at once. The normal gate
and state updates still apply.

## Metrics

Update metrics from evidence, not from the number of corrections shown:

- `recurring_error_rate`: recurring target errors divided by assessable messages;
- `spontaneous_correct_reuse_rate`: spontaneous correct target uses divided by transfer tests;
- `repair_success_rate`: passing immediate repairs divided by blocked repair attempts;
- `transfer_success_rate`: successful unannounced transfer uses divided by transfer tests;
- `average_unassisted_score`: average score before hints or corrections; and
- `blocked_message_rate`: blocked eligible messages divided by eligible messages.

The desired direction is recurring errors down, blocked messages down, spontaneous reuse up, and
average unassisted score up. These metrics guide target selection; they never replace the current
message score or the explicit `55` gate.
