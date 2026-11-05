---
name: dev-flow
description: "My end-to-end development flow from initiative to merged PR, built on Matt Pocock's skills and ponytail and split across two harnesses: Codex plans (wayfinder, grilling, to-spec, to-tickets, triage) and Claude Code builds and reviews with persona subagents. Use when starting or continuing feature work, choosing the next skill, handing tickets from Codex to Claude Code, or choosing personas and models for subagents."
---

# Dev flow

Matt Pocock's main flow, which `/ask-matt` routes, split across two harnesses: Codex plans and Claude Code builds.
The `.scratch/` files defined by `~/.agents/skills/orca-tickets/issue-tracker.md`, or a repository's own tracker,
are the contract between them.

Start each fresh session with `/dev-flow` in Claude Code or `$dev-flow` in Codex, plus whatever I already know. The
prompt carries only the current state (such as "the PR is merged") and that session's limits, never this skill's steps.

## Intake

Before any phase work, fill this table. Infer each input from the working directory, `.task-workspace.json`, Git
(current branch, default branch, remotes), and `.scratch/`; then ask only for what is still missing or ambiguous, in
one numbered round with your inferred or recommended value as the default. When nothing is missing, state the inputs
in one line and start. Without a named phase, propose one from the state: no spec means planning, unresolved tickets
mean execution, all tickets resolved mean review, an open PR means delivery, and a merged PR means close-out.

| Phase | Inputs | Usually inferred from |
|---|---|---|
| planning | goal; repositories in scope; level (initiative, epic, or single session); constraints or deadline | workspace goal and repositories; level from the goal's size |
| execution | spec path; integration branch; target branch | the one `.scratch/<feature>/spec.md`; `feat/<feature>`; the default branch |
| review | spec path; integration branch; target branch | same as execution |
| peer review | branch; target branch; spec location; extra focus (optional) | current branch; `dev` when it exists; a spec link or path in the PR or ticket |
| delivery | integration branch; target branch; ticket or issue link (optional) | current branch; target from review |
| close-out | merged PR link or merge commit | the remote target branch containing the integration branch |

## Levels

| Level | Artifact | Harness | Skills |
|---|---|---|---|
| Initiative: too big or foggy for one session | `.scratch/<effort>/map.md` and decision tickets | Codex | `/wayfinder` |
| Epic: a buildable feature that spans sessions | `.scratch/<feature>/spec.md` | Codex | `/grill-with-docs`, then `/to-spec` |
| Task | `.scratch/<feature>/issues/NN-<slug>.md` | Codex | `/to-tickets`, then `orca-tickets` |
| Incoming bug or request | a ticket moved to `ready-for-agent` | Codex | `/triage` |
| Execution | one integration branch, one merge per ticket | Claude Code | `/implement-spec`, or `/implement` for one ticket |
| Review | Spec, Standards, and Quality reports, then a cross-review | Claude Code, then Codex | `/code-review`, `/ponytail-review`, `codex review` |
| Delivery | a Bitbucket PR | Claude Code | `/pr` for the body |
| Upkeep | fixes to checks, standards, and steering files | either | `/retro`, `/ponytail-debt`, `/ponytail-audit` |

## Planning in Codex

- Codex stops at approved tickets and does not edit code.
- Keep `/grill-with-docs`, `/to-spec`, and `/to-tickets` in one session. Record decisions the spec cannot hold as
  ADRs or `GLOSSARY.md` entries while grilling; the spec and tickets are then the whole handoff, without `/handoff`.
- Ask of every requirement whether it needs to exist, and list what was cut under the spec's Out of Scope.
- Before `/to-spec`, when the feature crosses components or moves money, spawn the `platform_lens`,
  `security_lens`, and `reliability_lens` agents on the draft and grill me only on their open questions.
- After I approve the tickets, move planning drafts outside `.scratch/` (plans, spec drafts, ticket drafts) into
  `.scratch/<feature>/drafts/`, so the spec and tickets are the only planning files left in the workspace.
- Give each ticket a `Persona:` line with exactly one value: `backend-go`, `platform-engineer`, `devops`, or
  `implementer`. A ticket that needs two personas is two tickets.
- Mark a ticket `Risk: high`, followed by a one-line reason, only when its own change moves money or changes
  concurrency, data migrations, or auth; otherwise write `Risk: normal`. Documentation-only tickets are never high.
- Plan at `xhigh` effort; use `ultra` only to fan out parallel research.

## Building in Claude Code

- Start with `/implement-spec .scratch/<feature>/spec.md`, in a fresh session.
- The orchestrator reads only the spec, the tickets, and the `AGENTS.md` or `CLAUDE.md` files. Drafts, research
  notes, and code exploration go to an `Explore` subagent that returns pointers.
- When a ticket has no `Persona:` line, choose one from the code it touches, write it into the ticket, and say so in
  the report; add `Risk: high` the same way when the ticket meets that rule.
- Single-session work stays in Claude Code: `/grill-with-docs`, then `/implement`. If it outgrows the session, run
  `/to-spec` and `/to-tickets` there while the grilling is still in context, then continue in fresh sessions.
- Hard bugs go to `/diagnosing-bugs`; pipeline failures go to the `devops` persona.

| Role | Agent | Model |
|---|---|---|
| Orchestrator: frontier, merges, decisions | main session | Opus |
| Exploration notes for the tickets | `Explore` | its default |
| One ticket, by its `Persona:` line | `backend-go`, `platform-engineer`, `devops`, or `implementer` | Sonnet |
| Merger into the integration branch | `implementer` | Sonnet |
| Spec and Standards axes of `/code-review` | `validator`, one per axis | Sonnet |
| Quality axis, the `/ponytail-review` checklist | `validator` | Sonnet |
| Refute each finding before it is fixed | `verifier`, one per finding | Haiku |
| Fix lean and smell findings | `simplifier` | Sonnet |
| Fix bug findings | the ticket's persona | Sonnet |
| Extra review on `Risk: high` | `security-reviewer` and `reliability-reviewer` | Opus and Sonnet |
| Escalation | the same agent with `model: fable` | Fable |

- Escalate to Fable only for a ticket whose implementer failed twice, or for the security review of a `Risk: high`
  diff. Fable bills to usage credits at about 2.5 times the Opus price, so it is never a default.
- Run implementers with `isolation: worktree`. Those worktrees start from the default branch, so each implementer
  resets onto the integration branch first, as `/implement-spec` requires.
- Keep subagent reports to pointers (commits, files, ticket paths) so the orchestrator stays in its smart zone.
- Keep one session per phase or feature and `/clear` between unrelated work; the auto-compact window caps a session
  as a backstop, not a plan.
- Keep a workflow under 20 agents, and use ultracode only when I ask for it.
- When the `orca` CLI is on `PATH`, mirror the feature's stage on its worktrees with
  `orca worktree set --worktree path:<worktree> --workspace-status <in-progress|in-review|completed>` and the open
  frontier in `--comment`. Skip this silently when the CLI is missing or a call fails; `.scratch/` stays the source
  of truth.
- Use Orca workers through the `orca-tickets` skill instead of subagents when tickets are long or I want to watch
  each one in its own pane.

## Review and delivery

- After the Claude review passes, Codex cross-reviews from the integration branch:
  `codex review --base <branch the feature targets> "Review against .scratch/<feature>/spec.md"`. Claude Code fixes
  what survives a `verifier` pass.
- The local tracker closes work with `Status: resolved`, so `/implement-spec` opens no PR. Push the integration
  branch, write the body with `/pr`, and open the PR in Bitbucket. Do not install `gh` for this.
- At delivery, append a `## Flow metrics` section to the spec: dates of the first grilling and the PR, Codex and
  Claude sessions used, questions or fixes about already-decided items, and review findings raised versus those that
  survived the `verifier`.
- After the merge, close out in a fresh session: confirm every workspace commit is on the remote source branch and
  every ticket is `Status: resolved`, write the flow metrics, run `/retro`, then report whether the workspace can go
  to `task-workspace-archive` without archiving it, since archiving moves `.scratch/` out of the worktree.
- In `/retro`, also run `/ponytail-debt` and turn shortcuts with no upgrade trigger into `needs-triage` tickets.
- My gates: scope after grilling, seams in `/to-spec`, the breakdown in `/to-tickets`, review findings, and the merge.

## Reviewing another developer's branch

The phase is `peer review`; Intake gathers the branch, its target branch, and where the spec lives.

- Diff from the merge-base with the fetched target branch. Read a spec in a private Bitbucket repository from a local
  checkout with `git -C <checkout> fetch origin main` and `git show origin/main:<path>`, never by fetching the URL. If
  the spec changed after the branch started, say what changed and review against the version the developer had.
- Review in this order: correctness against the spec (each state and transition, idempotency, redelivery, crash
  windows, finalizers and cleanup, event order, status); reuse, naming the existing helper, pattern, or reconciler and
  how much code it would remove; then what can be cut, including work beyond the spec.
- Apply the `Risk: high` rule to the branch as a whole. Run the review as one workflow when the diff spans several
  packages or I ask for one; otherwise `/code-review` and `/ponytail-review` are enough.
- Stay read-only in every repository: no edits, commits, or pushes.
- Report in Portuguese: a verdict (approve, approve with notes, or request changes), spec coverage per requirement
  (done, partial, missing, or beyond the spec), confirmed findings ranked by severity with file:line, failure
  scenario, and suggestion, and the same findings as comments ready to paste into the Bitbucket PR, in a colleague's
  tone.
