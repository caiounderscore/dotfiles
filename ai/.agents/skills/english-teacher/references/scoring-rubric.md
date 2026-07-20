# Strict English scoring rubric

This is the single source of truth for scoring in the always-on English Notes routine,
`english-teacher`, and English language warm-ups.

This rubric applies prospectively from 2026-07-10. Keep earlier repair rows as historical
records and treat the summary counts at adoption as the baseline; do not reinterpret or
recalculate old entries under the stricter evidence rules.

Read the recurring-error summary before scoring. For each category affected by the current
message, calculate an effective count as `stored count + 1`; classify and score using that
effective count, then write the increment to the log. This makes the third occurrence chronic
rather than delaying the chronic penalty until the fourth.

## Canonical recurrence categories

Use these exact category names in new summary updates, error rows, and repairs:

| Canonical category | Includes |
|---|---|
| Spelling | spelling and typographical errors |
| Capitalization and punctuation | capitalization, punctuation, apostrophes, and contraction mechanics |
| Articles, prepositions, and natural phrasing | articles, prepositions, collocations, literal translations, sentence structure, and unnatural phrasing |
| Verb forms and agreement | verb form or tense, subject-verb agreement, and number agreement |
| Conjunctions and fixed expressions | conjunctions, fixed expressions, and phrasal verbs |
| Word choice | an incorrect general word or semantic contrast not covered above |
| Technical terminology | incorrect official technical, product, or feature names |

Historical error rows contain shorter aliases such as `article`, `phrasing`, `verb form`, and
`terminology`; map new instances to the canonical names above and do not create new aliases.
When one correction span could fit more than one category, choose the category that best
describes the required correction and do not count that span twice. Category-level recurrence
is intentionally strict: once a canonical category is chronic, a new error in that category
inherits chronic status even if its exact wording is new.

## Classification

- **First-time**: the effective count is one.
- **Logged, non-chronic**: the effective count is two.
- **Chronic**: the effective count is three or more.
- **Trivial/mechanical**: spelling, capitalization, apostrophe, or punctuation errors that do
  not change the intended meaning.
- **Substantive**: grammar, agreement, articles, prepositions, word choice, collocation, or
  literal-translation errors that reduce clarity or naturalness. Treat a mechanical error as
  substantive when it changes meaning.

Recurrence and severity are independent: an error may be both chronic and trivial. Grade
standard professional English even in short chat messages. Do not invent errors for rigor or
penalize valid variants, code, commands, paths, quoted text, or clearly deliberate stylization.

## Calculation

Start at 100. Use this deduction table:

| Category state | Trivial/mechanical | Substantive |
|---|---:|---:|
| First-time | -2 | -4 |
| Logged, non-chronic | -4 | -7 |
| Chronic | -6 | -10 |

Within each affected category, charge the highest-severity error first at the full table
amount. For every additional distinct error in that category, charge half the table amount
for that error's own severity, rounded up. A distinct error is a separate text span requiring
an independent correction; repeating the same mistake in another span counts again. Charge
each span once, using the canonical-category rule above.

After deductions, apply the strictest relevant hard cap:

- any logged, non-chronic error: 85;
- one chronic category containing only trivial/mechanical errors: 80;
- one chronic category containing a substantive error: 75;
- two chronic categories in the same message: 65;
- three or more chronic categories in the same message: 55.

The final score is the lower of the raw score and the applicable cap, with a floor of zero.
Show the arithmetic compactly, for example: `100 - 6 - 3 = 91; chronic-trivial cap 80 -> 80`.
Do not soften the result merely because the message remains understandable. A short clean
message may score 100, but its brevity is not evidence that a recurring pattern was repaired.

## Response gate

Apply the gate after calculating the final score for user-authored English:

| Final score | Required behavior |
|---:|---|
| 80–100 | Handle the request normally and append English Notes with concise tips. |
| 55–79 | Handle the request normally, append English Notes, and label the category mini-drills as `Required practice`. |
| Below 55 | Do not perform or substantially answer a non-urgent request yet. Give English Notes, ask the user to rewrite the request using the correction, and resume the original request as soon as a rewrite scores 55 or higher. |

The gate is instructional friction, not a safety boundary. Regardless of score, provide the
minimum complete response needed for:

- active incidents, production degradation, outages, or other time-sensitive operational work;
- security, privacy, credential exposure, data-loss prevention, or personal-safety concerns;
- clarification or refusal needed to avoid an unsafe, destructive, or unauthorized action;
- accessibility needs; and
- the language correction, drill, or warm-up itself.

For an exception, handle the urgent or protective part, still append English Notes, and ask
for a corrected rewrite only after the immediate risk is addressed. Do not use the gate to
withhold a safety refusal or a necessary clarifying question. Continue excluding quoted text,
code, logs, commands, and paths from scoring. The gate uses the current message's final score;
do not invent rolling averages, probation periods, or additional thresholds.

## Log and repair evidence

- For a message containing one or more errors, append one error-log row and increment each
  affected category once, even when the score includes extra deductions for multiple errors
  in that category.
- Use only the canonical category names in new log entries.
- Decrement a recurring category by one only when the message correctly exercises a specific
  failed target already present in the summary note, an earlier error row, or a queued drill.
  The repair row must name that target and cite its prior log evidence. A merely correct but
  unrelated construction in the same broad category, absence of the error, avoidance of the
  construction, or a message too short to test it is not repair evidence.
- If the same category contains an error in the current message, increment it and do not also
  decrement it.
- Acknowledge real repairs, record them in the Repairs table, and provide one mini-drill for
  every recurring category that appeared.
