# Recurring patterns and drills

Use pattern-level evidence in addition to the seven canonical categories. Historical examples
are diagnostic evidence, not a script to repeat. Vary the situation, especially when testing a
repaired construction.

## Priority patterns

| Pattern ID | Canonical category | Natural target | Portuguese-transfer warning |
|---|---|---|---|
| `direct_question_inversion` | `verb_forms_and_agreement` | *What steps does the team need to follow?* | Do not retain statement order in a direct question. |
| `modal_plus_base` | `verb_forms_and_agreement` | *The limit could depend on worker size.* | A modal takes the bare verb. |
| `lets_plus_base` | `verb_forms_and_agreement` | *Let's implement the validation first.* | Do not add `to` after *let's*. |
| `this_vs_these` | `verb_forms_and_agreement` | *Push these changes now.* | Match the demonstrative to noun number. |
| `articles_and_countability` | `articles_prepositions_natural_phrasing` | *Write an ADR and check the logs.* | Add or omit articles according to specificity and countability. |
| `fixed_prepositions` | `articles_prepositions_natural_phrasing` | *It depends on the load and focuses on cost.* | Memorize collocations, not Portuguese prepositions. |
| `discuss_without_about` | `articles_prepositions_natural_phrasing` | *Let's discuss the approach.* | *Discuss* takes a direct object. |
| `natural_collocation` | `articles_prepositions_natural_phrasing` | *Keep it in mind; make an exception.* | Prefer idiomatic English to a literal translation. |
| `then_vs_than` | `conjunctions_and_fixed_expressions` | *Commit and then push it; this is safer than that.* | Sequence and comparison are different. |
| `subject_and_auxiliary` | `verb_forms_and_agreement` | *The test is in two hours.* | English does not silently drop the subject or copula. |
| `technical_name` | `technical_terminology` | *Kubernetes, AWS, PostgreSQL, OpenTofu, gcloud.* | Use official names, but do not let terminology dominate grammar. |

## Foundational drills retained from the original skill

These remain available for focused practice and are still tracked at the pattern level:

- **PT-cognate spelling:** `recommend`, `exercises`, `mandatory`, `recurrent`, `errors`,
  `option`, `focus`, and `AI`. Drill: *I recommend the mandatory exercises to fix recurring
  errors.*
- **Dropped auxiliary/copula:** *We're talking about the rollout; the test is in two hours.*
- **Articles:** *Open a PR and put the diagram in the docs folder.*
- **Prepositions/collocations:** *This approach is preferable to the other; it depends on the
  load and focuses on cost.*
- **Subject–verb agreement:** *The metrics are noisy, but the root cause is clear.*
- **PT-literal phrasing:** prefer *I have 10 years of experience working with...*, *ask a
  question*, and *make a decision*.

Useful professional forms remain: *Yesterday I ...; today I'll ...; I'm blocked on ...*;
*What and why → how to test → risk/rollback*; *Impact, timeline, root cause, remediation,
action items*; and *Context → Decision → Alternatives considered → Consequences*.

## Portuguese-interference detector

Classify a phrase before correcting it:

- `WRONG`: *What is the steps the team needs do?* → repair structure and meaning.
- `UNDERSTANDABLE_BUT_UNNATURAL`: *keep in your mind* → *keep in mind*; *open an
  exception* → *make an exception*.
- `NATURAL`: *Keep the rollback plan in mind.*
- `NATIVE_LIKE`: *Let's keep the rollback plan in mind while we compare the options.*

Meaningful naturalness targets include *get back to*, *responsible for*, *built on top of*,
*contract for dedicated capacity*, *a rationale for*, *using `gcloud`*, and *the reason for
adding*. Do not “correct” a valid regional or technical variant merely because it is not your
preferred wording.

## Technical English

Normalize official terminology such as `Go`, `Kubernetes`, `AWS`, `GCP`, `PostgreSQL`, `NATS`,
`PowerDNS`, `OpenTofu`, `Bitbucket Pipelines`, `CI/CD`, `AI`, `AI agent`, `Kubernetes credentials`,
and `gcloud`. Terminology is normally severity 1 or 2; raise it only when it changes technical
meaning. Keep technical contexts dominant in sessions, but use general-life contexts to test
transfer beyond memorized work sentences.

## Drill design

For a repair or drill, vary:

1. professional contexts: Kubernetes, SRE, cloud infrastructure, architecture, incidents,
   code review, planning, and technical meetings;
2. general contexts: travel, university, daily life, opinions, preferences, and plans; and
3. grammatical shape: question, explanation, comparison, instruction, and narrative.

Do not repeat the historical corrected sentence. For *then/than*, for example, use new pairs
such as *Finish the migration, then restart the worker* and *This approach is safer than the
previous one*.
