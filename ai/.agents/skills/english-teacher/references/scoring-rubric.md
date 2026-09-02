# Adaptive English scoring rubric

This is the scoring source of truth for `english-teacher`, the always-on `English Notes`
routine, and English warm-ups. Apply it to intentionally English, user-authored prose only.
Do not score Portuguese, German exercises, code, commands, paths, logs, stack traces, JSON,
YAML, Terraform, Kubernetes manifests, quoted documentation, pasted third-party text, or
generated output.

## Canonical categories

Use these stable IDs for all new state, repairs, and log rows. Display labels may be used in
feedback. Historical aliases remain readable but must map to an ID rather than creating a new
category.

| ID | Display label | Includes |
|---|---|---|
| `spelling` | Spelling | spelling and typographical errors |
| `capitalization_and_punctuation` | Capitalization and punctuation | capitalization, punctuation, apostrophes, and contraction mechanics |
| `articles_prepositions_natural_phrasing` | Articles, prepositions, and natural phrasing | articles, prepositions, collocations, literal translations, sentence structure, and naturalness |
| `verb_forms_and_agreement` | Verb forms and agreement | tense, verb forms, subject–verb agreement, and number agreement |
| `conjunctions_and_fixed_expressions` | Conjunctions and fixed expressions | conjunctions, fixed expressions, and phrasal verbs |
| `word_choice` | Word choice | incorrect general words or semantic contrasts |
| `technical_terminology` | Technical terminology | official technical, product, or feature names |

Do not count one correction span twice. Prefer the category that describes the required
correction. Keep the existing human-readable history intact; normalize only new entries.
For a message containing errors, append one error-log row and increment each affected canonical
category once, even when several distinct spans in that category receive deductions.

## Severity and classification

Severity is independent of recurrence:

| Severity | Meaning | Typical examples | Default base penalty |
|---:|---|---|---:|
| 1 | Cosmetic/mechanical | missing final period, lowercase opening, `Ok` → `Okay`, minor technical capitalization | 3 |
| 2 | Lexical/localized | spelling, wrong technical capitalization, wrong word form, `than` → `then` | 6 |
| 3 | Structural/naturalness | article or preposition error, demonstrative disagreement, Portuguese-influenced collocation, wrong verb complement, countability | 10 |
| 4 | Major structural | malformed direct question, missing subject, incorrect modal, major reconstruction, ambiguous meaning | 14 |

Use the default inside the requested ranges (`-2..-4`, `-4..-7`, `-7..-12`, `-10..-15`).
Use a lower or higher value within that range only when the specific context justifies it and
show the reason in score arithmetic. Do not invent an error for a valid variant.

Naturalness classification for Portuguese interference:

- `WRONG`: grammar, meaning, or collocation is incorrect; usually severity 3 or 4.
- `UNDERSTANDABLE_BUT_UNNATURAL`: meaning is clear but the construction is a literal or
  non-idiomatic transfer; usually severity 2 or 3 and still receives meaningful weight.
- `NATURAL`: no deduction.
- `NATIVE_LIKE`: no deduction and possible positive transfer evidence when it exercises a
  known target.

## Deterministic calculation

Start at `100`. For each distinct error span calculate:

```text
penalty = round_half_up(base_penalty[severity] × recurrence_multiplier × confidence)
```

Use these multipliers:

```text
new pattern/category:       1.00
known recurring pattern:    1.35
high-frequency pattern:     1.60
```

`confidence` is `1.0` for high-confidence corrections, `0.9` for a plausible correction with
context, and `0.75` when the wording may be a valid variant. Do not charge a low-confidence
correction merely to lower a score.

An error is known when its pattern is active in state or its canonical category has prior
evidence. A pattern is high-frequency only when the exact pattern has at least five historical
errors and appeared in the recent-message window; a large lifetime category count alone is
never enough. Historical counts set training priority, not unlimited punishment.

Keep the recommended competence balance visible when choosing and reviewing deductions:

```yaml
grammar_and_structure: 30
natural_phrasing_articles_prepositions: 30
word_choice: 15
fluency_and_clarity: 15
surface_correctness: 10
```

Surface correctness is a budget, not a second score: total mechanical deductions for spelling,
capitalization, punctuation, and technical capitalization are capped at `10` for one message.
If a surface error changes meaning, classify it as substantive and charge it outside this
budget. This explicit protection means `Okay, go ahead.` cannot be blocked by typography alone.
Structural and naturalness penalties are never replaced by the surface cap.

Clamp the final result to `0..100`. For every blocked message, persist a `blocking_reason` made
of the visible deduction list; it must be reproducible from the scored spans. Show enough
arithmetic to reproduce it, for example:
`100 - round(14×1.35) - round(10×1.60) - 3 = 62; final 62`. The threshold is a communication gate, not a
claim that `55` is good English.

## Score bands and gate

The hard gate constant is:

```text
MINIMUM_SCORE = 55
```

| Score | Interpretation | Behavior |
|---:|---|---|
| 95–100 | Excellent / essentially natural | normal answer; concise notes |
| 90–94 | Very strong | normal answer; concise notes |
| 80–89 | Good, noticeable issues | normal answer; concise notes |
| 70–79 | Functional, important patterns remain | answer; `Required practice` drills |
| 55–69 | Weak but acceptable for continuing | answer; `Required practice` drills |
| 0–54 | Repair required | block non-urgent underlying task |

The response contract remains compatible with the shared `English Notes` routine:

| Final score | Required behavior |
|---:|---|
| 80–100 | Handle the request normally and append English Notes with concise tips. |
| 55–79 | Handle the request normally, append English Notes, and label the category mini-drills as `Required practice`. |
| Below 55 | Do not perform or substantially answer a non-urgent request yet. |

Apply the gate after scoring and before task execution:

```text
if score < 55 and no urgent/protective exception:
    preserve pending_task
    persist blocking_reason = visible deduction list
    return diagnosis + active rewrite exercise
else:
    answer the task
```

The gate must correspond primarily to multiple important recurring errors, serious structural
failure, or loss of clarity. A minor-only message remains above the threshold. Regardless of
score, provide the minimum complete response needed for:

- active incidents, production degradation, outages, or other time-sensitive operational work;
- security, privacy, credential exposure, data-loss prevention, or personal-safety concerns;
- clarification or refusal needed to avoid an unsafe, destructive, or unauthorized action;
- accessibility needs; and
- the language correction, drill, or warm-up itself.

For an urgent or protective exception, address the immediate risk, still append English Notes,
and request a corrected rewrite only after the risk is handled.

## Repair and positive evidence

When blocked, show at most three pedagogically valuable targets. Mark recurring targets with
`🔁` and new ones with `🆕`. Give hints and fragments, not normally the full corrected request.
The user must reconstruct it.

When a rewrite scores `>=55`, record an immediate repair for every specific failed target it
actually exercises, mark the pattern `transfer_pending`, and resume the preserved task. An
immediate repair improves the current interaction but does not prove mastery.

For a passing immediate repair that exercises a specific failed target, decrement the current
priority/category count once under the existing repair convention and record the cited
before→after value in the Repairs table. Do not decrement more than once per category for one
message, and do not decrement a category that still contains an error in that message. Keep
lifetime `errors` monotonic; later unprompted success is the stronger evidence for reducing
pattern recurrence priority.

For an unprompted correct use of a previously failed pattern, record `positive_evidence` with
`type: spontaneous` and decrement that pattern's open recurrence priority once. After multiple
spaced spontaneous successes, move the pattern through `improving` to `stable`. Do not
acknowledge every success and never claim mastery from absence of an error or from copying a
correction.
