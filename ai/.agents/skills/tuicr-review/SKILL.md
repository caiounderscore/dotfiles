---
name: tuicr-review
description: Process human tuicr comments from repository-scoped local review sessions after an explicit Review ready trigger. Evaluate each comment as APPLY, KEEP, CLARIFY, or DEFER before making focused, validated changes.
license: For personal use.
---

# Local tuicr Review Workflow

Use this skill only after the human explicitly says `Review ready.`, `Read my
tuicr review.`, or `Process the review comments.` It is an on-demand workflow.
Do not poll tuicr, add hooks, watch files, run a daemon, or reopen the TUI.

## Scope and identity

The current directory is the task-workspace root. It may contain multiple
immediate child Git repositories or worktrees. A comment is identified by:

```text
<repository>/<session>/<comment-id>
```

Never treat a comment ID as globally unique. Inspect only immediate child
directories (including legacy symlinked repository children), validate each as
an exact Git repository/worktree root, and ignore non-repository children.

For every repository, discover sessions with the repository-scoped native CLI:

```bash
tuicr review list --repo "$repo"
```

Select local sessions relevant to the current review, preferring active
sessions and sessions with comments. Then read comments with both repository
and session scope:

```bash
tuicr review comments --repo "$repo" --session "$session"
```

The commands return structured JSON. Use the stable comment `id`, repository,
session, and fields such as `path`, `start_line`, `end_line`, `side`,
`comment_type`, `lifecycle_state`, and `content`. Do not parse exported
Markdown when the structured CLI is available. Do not use an unscoped global
session and guess which repository it belongs to. Do not call `tuicr review add`
or otherwise create, edit, delete, resolve, or impersonate human comments.

During one agent conversation, avoid reprocessing an unchanged comment already
dispositioned in that conversation. If the agent session is restarted, reread
unresolved comments and evaluate them against the current code.

## Repository instructions and evidence

Before evaluating or editing a comment, identify that repository's Git root and
inspect its applicable `AGENTS.md`, `CLAUDE.md`, local instructions, ADRs,
contracts, architecture documentation, tests, and current Git state. Do not
assume instructions from one child repository apply to another. Inspect the
code surrounding the comment and relevant local documentation before deciding.

Human comments are review input, not unconditional commands. Evaluate them
against the task goal and approved scope, current code, tests, repository
patterns, contracts, architecture decisions, correctness, simplicity, and
cross-repository impact.

## Required disposition

The agent disposition is a closed enum. Every new human comment must receive
exactly one, and only one, of these four values:

```text
APPLY
KEEP
CLARIFY
DEFER
```

Never invent, substitute, combine, or nest another disposition value. In
particular, these words are prohibited as disposition labels:

```text
DISCUSS  REJECT  ACCEPT  BLOCKED  DEPENDENT  ANSWER  SUPERSEDED
SKIP     FIX     WONTFIX  PENDING
```

They may appear only as explanatory prose or in this prohibition, never in the
disposition column or summary. For example, use `CLARIFY` with a dependency in
the rationale, not `DISCUSS / dependent`; use `KEEP` when the current code
should remain, not `REJECT`.

These are agent dispositions, not tuicr comment types. The human types remain
exactly `CONTRAST`, `SIMPLIFY`, `CHALLENGE`, `CONTRACT`, `VERIFY`, `QUESTION`,
`INTENT`, plus native untyped `None`. Never add the four dispositions to the
tuicr selector, and never infer a disposition directly from a human type.

Before editing any file, classify every new human comment and present the
complete pass grouped by repository, using the stable repository/session/comment
identity and comment type:

```text
Review disposition

repo-a

  <comment-id> — <TYPE> — APPLY
  Reason: ...

  <comment-id> — <TYPE> — KEEP
  Reason: ...

  <comment-id> — <TYPE> — CLARIFY
  Depends on: <decision>
  Reason: ...

Summary
  APPLY:   1
  KEEP:    1
  CLARIFY: 1
  DEFER:   0
```

The summary must contain only `APPLY`, `KEEP`, `CLARIFY`, and `DEFER`. Verify
that every new comment appears exactly once and that:

```text
APPLY + KEEP + CLARIFY + DEFER = number of new review comments
```

No comment may silently disappear. Do not edit until this reconciliation is
complete.

Use `APPLY` only when the feedback is valid, the desired change is sufficiently
clear, it is within approved scope, and no unresolved dependency or decision
blocks implementation. `KEEP` means the current implementation remains
unchanged. It includes technically incorrect suggestions, authoritative
constraint conflicts, evidence supporting the current approach, a human
challenge that the current code wins, `VERIFY` → `NOT_CONFIRMED`, and a
`QUESTION` requiring no code change. A `KEEP` rationale is mandatory; it
describes the resulting code state and does not reject the reviewer.

Use `CLARIFY` when a decision is required before editing: ambiguous intent,
multiple materially different valid implementations, unresolved product or
architecture decisions, unresolved cross-repository ownership, dependent
comments that cannot be decided independently, `VERIFY` → `AMBIGUOUS`, or a
`CONTRACT` concern whose intended behavior is not established by repository
evidence. Use `DEFER` when the concern is valid but outside the approved task,
belongs to a separate feature, is a post-MVP improvement, or would materially
expand the current change.

Apply independent `APPLY` items after presenting the disposition. Do not edit
`KEEP`, unresolved `CLARIFY`, or `DEFER` items. An `APPLY` item that depends on
an unresolved `CLARIFY` decision must also be classified `CLARIFY`. Unrelated
independent APPLY items may proceed while another item remains CLARIFY.

## Type-specific reasoning

- `CONTRAST`: compare the implementation with task scope, repository patterns,
  constraints, alternatives, failure modes, and cross-repository effects before
  choosing a disposition.
- `SIMPLIFY`: actively seek speculative abstractions and needless indirection,
  without removing correctness, security, idempotency, failure handling,
  observability, or explicit contracts.
- `CHALLENGE`: investigate both the human suggestion and current implementation;
  either may be wrong. `KEEP` is valid when evidence supports the current code.
- `CONTRACT`: trace producer, consumers, schemas/APIs/CRDs, ownership, and
  compatibility. If a cross-repository change lacks explicit intent or migration
  policy, prefer `CLARIFY` and list affected repositories.
- `VERIFY`: first classify the concern internally as `CONFIRMED`,
  `NOT_CONFIRMED`, or `AMBIGUOUS`. Map these to `APPLY` when confirmed and clear,
  `KEEP` when not confirmed, and `CLARIFY` when ambiguous. Use `DEFER` if
  confirmed but outside scope.
- `QUESTION`: answer the question first; normally use `KEEP` when no code change
  is indicated. Use `APPLY` only if answering reveals a concrete in-scope
  defect, or `CLARIFY` if human intent is still required.
- `INTENT`: re-evaluate the outcome rather than mechanically implementing the
  comment wording; the current implementation may already satisfy it.

The type does not predetermine the disposition.

### Dependent comments

When multiple comments depend on one unresolved decision, assign `CLARIFY` to
every affected comment. Group them by the root decision, but keep every
repository and stable comment ID visible:

```text
Decision A — staging capacity policy

Affected comments:
- repo-a / <comment-id> — CLARIFY
- repo-b / <comment-id> — CLARIFY

Why blocked:
All comments depend on whether staging should optimize for minimum cost or
production similarity.

Decision needed:
Should staging optimize for minimum cost or production similarity?
```

Dependency is metadata in the `CLARIFY` rationale, never a new disposition.

When the human answers, re-evaluate only the affected comments. Each must
transition to `APPLY`, `KEEP`, `DEFER`, or remain `CLARIFY` if ambiguity still
genuinely remains. Do not create lifecycle dispositions such as `RESOLVED`,
`ACCEPTED`, `REJECTED`, or `DISCUSS`.

### Verification and questions

Keep verification state separate from disposition:

```text
CONFIRMED + clear/in-scope fix       → APPLY
NOT_CONFIRMED                        → KEEP
AMBIGUOUS                            → CLARIFY
CONFIRMED but outside current scope → DEFER
```

For example:

```text
repo-a / <comment-id> — VERIFY — KEEP
Verification: NOT_CONFIRMED
Reason: The proposed value violates the authoritative service constraint.
```

Likewise, a question normally becomes `KEEP` after it is answered without a
code change. It may become `APPLY` when the answer reveals a clear in-scope
defect, or `CLARIFY` when the human must decide the intended behavior. The
answer or verification result never replaces the canonical disposition.

## Cross-repository changes

A comment in repository A may expose an impact in repository B. Do not hide the
propagation. Name the producer, consumer, and all affected repositories in the
disposition. Before editing repository B, read B's instructions, inspect the
actual consumer, and verify the impact. Never modify repositories outside the
current task workspace; use `CLARIFY` or `DEFER` instead.

## Apply, validate, and stop

After accepted changes:

1. run the smallest relevant checks in each changed repository;
2. run affected tests;
3. inspect the resulting diff and ensure unrelated files did not change;
4. report the mapping from each APPLY comment to changed files and validation.

Do not mark comments resolved or delete them. Stop at a coherent review
checkpoint so the human can run `review` and re-review the working-tree diff.
There is no automatic loop.

The task workspace may start outside Git, so a child repository's project
instructions, hooks, or root configuration may not have been loaded at session
start. Load them explicitly before work as described above. Do not create a
synthetic parent repository or modify provider discovery semantics to solve it.
