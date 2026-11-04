# Issue tracker: local markdown mirrored in Orca

The default tracker for repositories without their own `docs/agents/issue-tracker.md`. Specs and tickets are
markdown files on this machine; Orca mirrors them as orchestration tasks.

## Location

- Use the primary checkout's `.scratch/`, also from a linked worktree:
  `"$(git rev-parse --path-format=absolute --git-common-dir)/../.scratch"`.
- When creating `.scratch/`, also create `.scratch/.gitignore` containing `*`, so Git ignores it without a
  repository change.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`, with the spec in `spec.md`.
- One file per ticket at `issues/<NN>-<slug>.md`, numbered from `01` in dependency order, never one combined file.
- A `Status:` line near the top holds the triage role (`needs-triage`, `needs-info`, `ready-for-agent`,
  `ready-for-human`, `wontfix`), then `claimed` while someone works on it and `resolved` when done.
- A `Blocked by:` line lists ticket numbers, or `None`. A ticket is unblocked when every ticket it lists is
  `resolved`.
- A `Persona:` line names the one implementer agent for the ticket, and a `Risk: high` line with its reason marks a ticket that moves
  money or touches concurrency, data migrations, or auth. The `dev-flow` skill defines both.
- Comments append under a `## Comments` heading at the bottom.
- Domain docs are single-context: `GLOSSARY.md` and `docs/adr/` at the repository root. Proceed silently when they
  are absent.

## When a skill says "publish to the issue tracker"

Write the files above. When the `orca` CLI is available, then register them with the `orca-tickets` skill.

## When a skill says "fetch the relevant ticket"

Read the referenced file under `.scratch/`.

## Wayfinding operations

The map is `.scratch/<effort>/map.md`; child tickets follow the conventions above plus a `Type:` line
(`research`/`prototype`/`grilling`/`task`). Claim with `Status: claimed`. Resolve by appending an `## Answer`
heading, setting `Status: resolved`, and adding a context pointer to the map's Decisions-so-far.
