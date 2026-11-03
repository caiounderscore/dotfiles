---
name: orca-tickets
description: Mirror a spec's local tickets (.scratch/<feature>/issues/*.md) in Orca as one orchestration Run with a Task per ticket and its blocking edges, then dispatch the ready frontier to Orca workers. Use after to-spec or to-tickets publish local tickets, when the user wants Orca to track or implement those tickets, or to publish them to Jira through Orca when the user asks.
---

# Orca tickets

The ticket files stay the source of truth, as [issue-tracker.md](issue-tracker.md) defines them; Orca mirrors
them so it shows each ticket, its dependencies, and its worker. Resolve the `orca` executable as the `orca-cli`
skill describes, and pass `--json`.

## Register a feature

1. Read `.scratch/<feature>/spec.md` and every `issues/NN-*.md`. If `spec.md` already has an `Orca run:` line,
   reuse that Run with `--run <id>`.
2. Otherwise create one Run per feature with `orca orchestration run-create --objective "<feature>: <spec title>"`
   and write `Orca run: <run_id>` under the spec title.
3. In ticket-number order, create one Task per ticket that has no `Orca task:` line and is not `resolved` or
   `wontfix`:
   `orca orchestration task-create --run <run_id> --spec-file <ticket file> --task-title "NN: <title>" --deps '<json array>'`.
   Map each `Blocked by:` number to the Task id already created for it (`[]` when none), then write
   `Orca task: <task_id>` under the ticket's `Status:` line.
4. Show the user `orca orchestration task-list --run <run_id> --brief`.

- Inside an Orca terminal, pass this coordinator's handle as `--from`; find it in `orca terminal list --json` by the
  worktree of the current directory.
- Pass `--deps` as one quoted argument built with `jq -nc '$ARGS.positional' --args <ids...>`. zsh does not split an
  unquoted variable into words, so a hand-joined list breaks for tickets with several blockers.

## Implement the frontier

Only when the user asks to implement the tickets. Load `orca skills get orchestration` first; it governs the loop.

- Start each Task that `orca orchestration task-list --run <run_id> --ready --brief` lists, in its own workspace
  so parallel tickets never share a checkout:
  `orca orchestration worker-start --task <task_id> --run <run_id> --worktree new-top-level --repo <selector> --name <feature>-<NN> --base-branch <branch the feature targets> --agent claude --model sonnet`.
- End your turn; Orca wakes you. On each `worker_done`, set the ticket's `Status: resolved`, or append the failure
  under `## Comments`, then start whatever is newly ready.
- This replaces only implement-spec's implementer-subagent loop; its branch, merge, and review steps still apply.

## Jira, on request

Only when the user asks for Jira. `orca jira connection` must report `connected: true`; otherwise ask the user to
connect Jira in Orca. Publish the spec, then each ticket in dependency order:
`orca jira create --project <KEY> --type <issueTypeId> --title "<title>" --body-file <file>` (`orca jira project types`
lists type ids), then `orca jira label add <KEY-n> --label ready-for-agent`. Orca cannot create Jira issue links, so
start each body with `Blocked by: <KEY-n>, <KEY-m>`. Record `Jira: <KEY-n>` in the local file, and link workspaces
with `--reference <KEY-n>` on `orca worktree create`.
