# Dotfiles

A browsable GNU Stow repository. Each package mirrors paths relative to `$HOME`; Stow
creates links into place, so editing a managed home file edits this repository.

## Layout

```text
dotfiles/
├── ai/.agents/
│   ├── AGENTS.md                 # canonical personal instructions
│   └── skills/                   # user-owned portable skills only
├── claude/.claude/               # Claude settings and thin adapters
│   └── agents/                   # Role and persona subagents (implementers, reviewers, verifier)
├── codex/.codex/                 # Codex instructions and hook adapters
│   ├── agents/                   # Read-only planning lenses (platform, security, reliability)
│   └── mcp-profiles/             # Portable MCP safety policy; no cluster paths or credentials
├── openclaude/.openclaude/       # OpenClaude instructions adapter and tracked defaults
├── opencode/.config/opencode/    # OpenCode instructions adapter
├── tuicr/.config/tuicr/          # shared local-review configuration
├── zsh/                          # .zshrc, .aliases, .exports
├── git/                          # .gitconfig and work example
├── ghostty/                      # terminal configuration
├── vim/                          # .vimrc
├── yazi/                         # file-manager configuration
├── scripts/setup-ai.sh           # safe AI migration and Stow preview/apply
├── AGENTS.md                     # instructions for this repository
├── CLAUDE.md -> AGENTS.md
├── Brewfile
└── bootstrap.sh
```

Agent-agnostic means shared semantics with thin client adapters. It does not mean forcing
model selection, hooks, permissions, sandboxing, UI, or authentication into a fake universal
format. Those settings remain under their vendor packages or unmanaged runtime directories.

## AI configuration

### Neutral core

| Purpose | Canonical path |
|---|---|
| Personal instructions | `~/.agents/AGENTS.md` in the Stow package; adapters expose it to clients |
| User-owned skills | `~/.agents/skills/<name>/SKILL.md` |
| Dynamic language state | `~/.agents/state/language/` (untracked) |
| Per-machine warm-up opt-in | `~/.agents/state/language/warmup-enabled` (untracked) |
| Migration backups | `~/.agents/state/backups/ai-migration-<timestamp>/` (untracked) |

The repository intentionally vendors only personal portable skills: `reload`,
`session-report`, `language-warmup`, `english-teacher`, `german-teacher`, `tuicr-review`,
`orca-tickets`, `dev-flow`, `k8s-controller`, `bitbucket-pipelines`, and `igaming-correctness`. The 1,500+ installed third-party skills remain outside Git.

`~/.agents/.skill-lock.json` is also left unmanaged. The current file has safe provenance and
content hashes for 20 skills, but no pinned revisions and no coverage for most installed
skills, so it is useful for partial integrity checks—not full restoration.

### Client adapters and capability differences

| Capability | Codex | Claude Code | OpenClaude | OpenCode |
|---|---|---|---|---|
| Global instructions | `~/.codex/AGENTS.md` adapter | `~/.claude/CLAUDE.md` adapter | `~/.openclaude/CLAUDE.md` adapter | `~/.config/opencode/AGENTS.md` adapter |
| Personal skills | Reads `~/.agents/skills` directly | `~/.claude/skills` points to `~/.agents/skills` | OpenClaude-managed skills stay separate | Reads `~/.agents/skills` directly |
| Session warm-up | Machine-local `~/.codex/hooks.json`, seeded from the tracked baseline; marker-gated; review hook trust | User hook in `~/.claude/settings.json`; marker-gated | No tracked startup hook; rely on `CLAUDE.md` plus local user settings | No startup shell hook; invoke `language-warmup` manually |
| Model/UI/permissions | Existing `~/.codex/config.toml`, unmanaged | Machine-local `~/.claude/settings.json`, seeded once from the tracked baseline because Claude rewrites it at runtime; project-local overrides stay per repository | `~/.openclaude/settings.json`, unmanaged | `~/.config/opencode/opencode.json` or `opencode.jsonc`, unmanaged |
| Agent roles | Tracked `~/.codex/agents/` defines the read-only `platform_lens`, `security_lens`, and `reliability_lens` planning reviewers | Opus main session orchestrates; `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` for untyped subagents and workflow agents; tracked `~/.claude/agents/` defines `implementer`, `validator`, the `backend-go`, `platform-engineer`, `devops`, and `simplifier` personas, `reliability-reviewer` (Sonnet), `security-reviewer` (Opus), and `verifier` (Haiku) | Not configured | Not configured |
| Kubernetes MCP | Tracked safety profile + global registration helper; cluster paths stay local | Configure separately for Claude if needed | Configure separately in local OpenClaude settings if needed | Configure separately in `opencode.json` or `opencode.jsonc` if needed |
| Managed skills | `~/.codex/skills/.system`, never touched | Client/plugin-managed locations remain separate | `openclaude skills` inventory remains client-managed | No client-managed skill root to preserve |

Installed Codex 0.152.1 and Claude Code 2.1.206 both support `SessionStart` with
`startup`, `resume`, `clear`, and `compact`. The shared hook script stays silent unless the
per-machine marker exists, and also stays silent for resume and compact. Both adapters inject
only the neutral `language-warmup` skill. The injection includes its canonical
`~/.agents/skills/language-warmup/SKILL.md` path so an agent can load it even when a bounded
skill catalog omits it; provider lookup and the sandbox-safe fallback remain secondary paths.
Codex requires reviewing a new or changed hook; never bypass that trust review.

OpenClaude uses its own `~/.openclaude` config tree and supports `~/.openclaude/CLAUDE.md`,
so this repository tracks only that instruction adapter there. Keep OpenClaude provider
profiles, `settings.json`, installed skills, histories, sessions, and other runtime state
machine-local. The verified portable mapping from your older Claude setup is:

- track shared instructions through `~/.openclaude/CLAUDE.md`;
- keep local `~/.openclaude/settings.json` for `model`, `effort`, `permissionMode`, and provider choices;
- keep startup sounds, stop sounds, and other hook-like behavior in local OpenClaude plugins or workflows if you add them later.


Official discovery references: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[Codex skills](https://learn.chatgpt.com/docs/build-skills),
[Codex hooks](https://learn.chatgpt.com/docs/hooks),
[Claude instructions](https://code.claude.com/docs/en/memory), and
[Claude skills](https://code.claude.com/docs/en/skills),
[Claude settings](https://code.claude.com/docs/en/settings), and
[Claude hooks](https://code.claude.com/docs/en/hooks), plus
[opencode rules](https://opencode.ai/docs/rules/),
[opencode skills](https://opencode.ai/docs/skills/), and
[opencode plugins](https://opencode.ai/docs/plugins/).

### Safe migration from `~/.agent` to `~/.agents`

Preview first; this is read-only:

```sh
bash scripts/setup-ai.sh
```

The content and structure scan can take about a minute with roughly 3,000 installed skill
directories.

The preview:

- fails before migration if `~/.agents`, `~/.claude`, `~/.codex`, or `~/.openclaude` is a folded Stow link into
  this repository, preventing runtime writes from landing in Git;
- rejects source-package entries outside the documented shared files and client adapters, so
  Git-ignored runtime state cannot be linked by Stow;
- hashes paths, contents, link targets, and executable state for valid top-level skills, then
  reports identical, singular-only, plural-only, and conflicting names;
- plans copies for singular-only skills without overwriting canonical entries, resolving a
  top-level skill link into a real directory while preserving links inside the skill;
- excludes repository-managed language skills from generic copying;
- preserves same-name/different-content conflicts in both roots;
- simulates Stow for `ai`, `claude`, `codex`, `openclaude`, and `opencode`, skipping
  `claude/.claude/settings.json` and `codex/.codex/hooks.json`. Clients and tools such as Orca
  rewrite those at runtime, so each is copied only when the home file is missing, and an older
  Stow link to it becomes a machine-local copy;
- shows language-log migration, per-machine warm-up preference migration, backups, and link
  replacements.

After reviewing the preview, apply explicitly:

```sh
bash scripts/setup-ai.sh --apply
```

The script never deletes either skill root. It copies only absent singular-only skills,
keeps conflicts untouched, backs up every replaced live symlink, and points
`~/.claude/skills` at the plural canonical root. Existing English state migrates only when
the neutral destination is absent or identical. Divergent German logs are backed up and
stored under distinct `migration-conflicts/` names; no canonical German history is chosen
until the files are reconciled manually. If the old unsupported
`~/.claude/settings.local.json` contains the warm-up hook, its opt-in intent migrates to the
neutral marker; the file remains untouched and the script warns that any other keys need
manual review.

Relinking changes which same-name conflict is active in Claude: after migration, Claude uses
the plural-root version while the singular-root version remains available for review and
rollback. Review the conflict list before applying if version changes are a concern.

The legacy sources remain in place for rollback. To roll back a replaced link, inspect the
reported timestamped backup and move that saved symlink back only after previewing the
impact. Do not use `stow --adopt` or delete either skill tree.

If the folded-root preflight fails, inspect the reported package directory for runtime-only
files and back them up outside the repository. After separating runtime data from the tracked
adapters, unfold the relevant package with a reviewed `stow --restow --no-folding` operation,
restore runtime data into the resulting real home directory without overwriting managed links,
and rerun the preview. The migration does not automate this because folded roots can contain
auth, history, installed skills, and project state.

### Portable workflows and language coaching

- `reload` refreshes applicable instructions, relevant memory, Git state, and discussed
  files without assuming a client-specific memory command.
- `orca-tickets` is the default issue tracker for `to-spec`/`to-tickets` in repositories without
  their own config: markdown in the primary checkout's self-ignored `.scratch/`, mirrored in Orca
  as one orchestration Run per spec with a Task per ticket and its blocking edges. Jira through
  Orca is used only on request.
- `dev-flow` maps Matt Pocock's flow onto two harnesses: Codex owns wayfinding, specs, tickets, and
  triage; Claude Code implements with Opus orchestrating Sonnet implementers, reviews with Sonnet
  validators and Haiku verifiers, and escalates to Fable only on repeated failure or high-risk diffs.
  Tickets name their persona and risk; ponytail adds the Quality review axis and the shortcut ledger.
- `k8s-controller`, `bitbucket-pipelines`, and `igaming-correctness` are short checklists that the
  persona subagents preload or call where no vetted third-party skill exists.
- `session-report` gives evidence-grounded prompt/context feedback and includes usage only
  when a client already exposes authoritative metadata.
- `language-warmup` is manually invokable and is injected by supported startup hooks when the
  per-machine marker exists.
- `english-teacher` and `german-teacher` retain their complete teaching references while
  keeping progress under neutral, untracked state paths.
- `tuicr-review` processes human comments from repository-scoped local tuicr sessions after
  the explicit `Review ready.` trigger. It presents `APPLY`, `KEEP`, `CLARIFY`, or `DEFER`
  before editing and never polls or writes comments.
- The authoritative English rubric applies a client-agnostic response gate: scores below 55
  defer non-urgent work until a corrected rewrite, while urgent operational and protective
  responses remain available at every score.

If a sandbox cannot write language state, the skills request scoped approval or return a
copyable update. They never weaken a client's sandbox globally.

## Shell helpers

- `k` aliases `kubectl`.
- `klocal` and `kdev` switch the default kubeconfig to their named contexts, then optionally
  run a command.
- `ksandbox` points `KUBECONFIG` at the generated sandbox kubeconfig
  (`~/.bladecp-sandbox/talos/generated/kubeconfig`) for the session, and refuses when that file's
  current context is not `admin@bcp-sandbox-control-plane` (`K8S_SANDBOX_KUBECONFIG` and
  `K8S_SANDBOX_CONTEXT` override both).
- `kprod-auth` derives a temporary BladeCP production admin kubeconfig through the private
  runner; `kprod` scopes that file to one command, classifies operations fail-closed, and
  checks the Tailscale-routed API first; `kprod-clean` removes only that temporary credential.
  The API host and TLS name come from `K8S_PROD_API_HOST` and `K8S_PROD_TLS_SERVER_NAME` in
  untracked `~/.zshrc.local`; both commands refuse to run without them.
  Mutating `kprod` commands require typing `yes`.
- `reload` restarts the current shell with `exec zsh -l`.
- `codex` enables its native turn-scoped macOS idle-sleep inhibitor; the other AI clients keep
  their default sleep behavior.
- `docker` and `docker-compose` map to `nerdctl` and `nerdctl compose`.
- `task-workspace --from <source-branch> [--goal <objective>] <workspace-name>
  <repository...>` creates or reuses canonical Git worktrees and generates the task contract.
  It lives in `zsh/.task-workspace.zsh` with `workspaces`, which reports each workspace's
  repositories as clean, dirty, or unpushed, and `task-workspace-archive <name>`, which refuses
  dirty or unpushed worktrees, moves ignored files such as `.scratch` and the root files to
  `~/workspaces/.archive/`, and removes the worktrees while keeping their branches. When the Orca
  CLI is on `PATH`, `task-workspace` also makes the worktrees visible in Orca; nothing requires it.
- `skills` lists every skill in `~/.agents/skills`; `skills <term>` filters names and
  descriptions; `skills -d [term]` includes descriptions. Override the root with `SKILLS_DIR`.

The installed Codex feature `prevent_idle_sleep` prevents idle system sleep only while a turn
is actively running. An open Codex client waiting at the prompt does not hold the assertion, and
the display may still sleep. Start a fresh shell after installing or relinking the package;
direct invocations such as `command codex` bypass the wrapper. The feature is experimental in
Codex 0.152.1, so revalidate it after Codex upgrades.

### Managed task workspaces

`task-workspace` keeps its existing branch model: each repository uses the workspace name as
its target branch unless `--target-branch` is supplied, and the target branch is created from
the explicit `--from` branch only when it does not already exist. `--workspace` can still
override the default `~/workspaces/<workspace-name>` root.

```sh
task-workspace \
  --from main \
  --goal "Implement worker lifecycle while preserving existing repository contracts." \
  feat/worker-lifecycle \
  ~/projects/provision-worker \
  ~/projects/app-stack-operator
```

The workspace root contains `.task-workspace.json`, a concise generated `AGENTS.md`, and one
real Git worktree per repository. Canonical children are never symlinks or replacement
clones. A rerun validates and reuses matching worktrees, then regenerates both contract files.
An unrelated target path, mismatched repository/origin/branch, detached checkout, or target
branch checked out in another worktree is a hard failure that requires explicit user
resolution.

The shared Codex/Claude `SessionStart` hook resolves the nearest `.task-workspace.json` from
the session working directory and injects the goal, canonical root, and instruction to read
the workspace `AGENTS.md`. Repository-local `AGENTS.md` and `CLAUDE.md` files remain additive
and authoritative for repository-specific implementation rules.

### Local tuicr review

The `tuicr` Stow package configures the native comment-type cycle as
`CONTRAST`, `SIMPLIFY`, `CHALLENGE`, `CONTRACT`, `VERIFY`, `QUESTION`, `INTENT`,
then `None`. In a task workspace, use `review`, press `c` to create a comment,
and press `Tab` to select its semantic type. After writing comments, tell the
agent `Review ready.`; it reads each repository's persisted session through the
scoped `tuicr review` CLI and produces dispositions before editing.

The task-workspace root is not a Git repository by design. Its generated `AGENTS.md` defines
the canonical task boundaries, while each child's applicable instructions must still be
loaded when processing that repository; an agent started at the task root may not
automatically load every child's project-specific instructions, hooks, or root configuration.

## Containers and local Kubernetes

Containers run through [Colima](https://github.com/abiosoft/colima) with `containerd`,
driven by [nerdctl](https://github.com/containerd/nerdctl). Colima can also provision a
single-node k3s cluster.

```sh
brew bundle --file="$PWD/Brewfile"
colima start --runtime containerd --kubernetes
mkdir -p ~/.local/bin
colima nerdctl install --path ~/.local/bin/nerdctl
```

Colima is started manually rather than as a login service; stop it with `colima stop`.
It writes and activates a `colima` context in `~/.kube/config`. Colima disables bundled
Traefik and replaces ServiceLB with its port-forwarding cloud-controller-manager; CoreDNS,
local-path storage, and metrics-server remain.

## New-machine setup

```sh
git clone git@github.com:<you>/dotfiles.git /path/to/dotfiles
cd /path/to/dotfiles
./bootstrap.sh
```

`bootstrap.sh` derives its own repository path, installs the Homebrew and shell prerequisites
(including Go and `gopls` for the enabled Claude plugin), simulates Stow before applying it,
stows the base packages, then runs the
AI migration and stows `ai`, `claude`, `codex`, `openclaude`, and `opencode`. It does not install,
authenticate, or choose a default AI vendor. If a client is not installed, its configuration
remains ready for later use.

On an existing machine, run `bash scripts/setup-ai.sh` separately before bootstrap so the
live AI impact can be reviewed in isolation.

## Optional client setup

### Codex Kubernetes MCP

The tracked profile at `~/.codex/mcp-profiles/kubernetes-safe.toml` enables only the core
Kubernetes tools, denies Secrets, ServiceAccounts, and RBAC resources, validates writes, and
fails closed when a client cannot display confirmation for a destructive operation. The
server binary, kubeconfig, context, and resulting `~/.codex/config.toml` entry remain
machine-local.

Registering the server globally makes it available to every Codex workspace on that machine;
no project `.codex/config.toml` is needed. Preview first:

```sh
bash scripts/setup-codex-kubernetes-mcp.sh \
  --name ksandbox-kubernetes \
  --server ~/.local/bin/kubernetes-mcp-server-v0.0.64 \
  --kubeconfig ~/.kube/config-remote
```

The helper prints the one allowed context, API endpoint, version-pinned executable, profile,
and exact `codex mcp add` command. After review, repeat with `--apply`, then restart Codex:

```sh
bash scripts/setup-codex-kubernetes-mcp.sh \
  --name ksandbox-kubernetes \
  --server ~/.local/bin/kubernetes-mcp-server-v0.0.64 \
  --kubeconfig ~/.kube/config-remote \
  --apply
```

The helper rejects multi-context kubeconfigs and refuses to replace an existing MCP entry.
Use a separate, least-privilege kubeconfig and a distinct MCP name for every cluster; never
reuse a sandbox cluster-admin kubeconfig for production.

- Enable the bilingual startup warm-up on a machine by creating its untracked marker:

  ```sh
  mkdir -p ~/.agents/state/language
  touch ~/.agents/state/language/warmup-enabled
  ```

  Move that marker to another name to disable automatic warm-ups without deleting language
  progress. Manual use of the skill remains available.
- Claude: the hook is in the supported user-level `~/.claude/settings.json`. Claude only loads
  `.claude/settings.local.json` inside a project; it does not load
  `~/.claude/settings.local.json` as a global override.
- Codex: its hook adapter is stowed, but the client must approve it through the normal hook
  trust flow. Existing `~/.codex/config.toml` model, reasoning, personality, trust, and
  sandbox settings remain unmanaged and unchanged.

## Verification

```sh
git diff --check
bash -n bootstrap.sh scripts/setup-ai.sh scripts/setup-codex-kubernetes-mcp.sh
zsh -n zsh/.aliases zsh/.task-workspace.zsh
zsh scripts/test-ai-session.zsh
jq empty claude/.claude/settings.json codex/.codex/hooks.json
bash scripts/test-task-workspace.sh
bash scripts/test-ai-config.sh
bash scripts/setup-ai.sh
if command -v claude >/dev/null; then claude doctor; fi
if command -v codex >/dev/null; then codex --strict-config doctor --json; fi
```

Run ShellCheck on changed shell scripts when installed. The Codex doctor command is
non-billable but can report provider reachability separately from config parsing. Do not
start a networked agent session solely to verify discovery.

After applying, verify:

```sh
readlink ~/.claude/skills
readlink ~/.openclaude/CLAUDE.md
readlink ~/.config/opencode/AGENTS.md
if command -v codex >/dev/null; then test -f ~/.codex/skills/.system/.codex-system-skills.marker; fi
skills
skills agent
skills -d agent
skills english-teacher
skills german-teacher
```

## Daily use and per-machine overrides

Edit managed files in the repository and review the diff before committing. To add a package,
mirror its target path and run a Stow simulation before applying it.

Keep these machine-specific files untracked:

- `~/.zshrc.local` from `zsh/.zshrc.local.example` for proxy, PATH, and work settings;
- `~/.gitconfig-work` from `git/.gitconfig-work.example` for work identity;
- `<project>/.claude/settings.local.json` for Claude settings that apply only to that project;
- all language state, auth, histories, sessions, caches, databases, telemetry, and logs.

Claude has no machine-local global overlay named `~/.claude/settings.local.json`. Put global
user settings in `~/.claude/settings.json` or keep genuinely project-specific settings in that
project's `.claude/settings.local.json`.
