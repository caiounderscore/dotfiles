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
├── codex/.codex/                 # Codex instructions and hook adapters
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
`session-report`, `language-warmup`, `english-teacher`, and `german-teacher`. The 1,500+
installed third-party skills remain outside Git.

`~/.agents/.skill-lock.json` is also left unmanaged. The current file has safe provenance and
content hashes for 20 skills, but no pinned revisions and no coverage for most installed
skills, so it is useful for partial integrity checks—not full restoration.

### Client adapters and capability differences

| Capability | Codex | Claude Code |
|---|---|---|
| Global instructions | `~/.codex/AGENTS.md` adapter | `~/.claude/CLAUDE.md` adapter |
| Personal skills | Reads `~/.agents/skills` directly | `~/.claude/skills` points to `~/.agents/skills` |
| Session warm-up | Tracked `~/.codex/hooks.json`; marker-gated; review hook trust | User hook in `~/.claude/settings.json`; marker-gated |
| Model/UI/permissions | Existing `~/.codex/config.toml`, unmanaged | Tracked user settings; project-local overrides stay per repository |
| Managed skills | `~/.codex/skills/.system`, never touched | Client/plugin-managed locations remain separate |

Installed Codex 0.144.1 and Claude Code 2.1.206 both support `SessionStart` with
`startup`, `resume`, `clear`, and `compact`. The shared hook script stays silent unless the
per-machine marker exists, and also stays silent for resume and compact. Both adapters inject
only the neutral `language-warmup` skill. Codex requires reviewing a new or changed hook;
never bypass that trust review.

Claude officially supports a `CLAUDE.md` symlink to `AGENTS.md` and symlinked personal skill
entries. This setup also uses a containing `~/.claude/skills` link; its filesystem traversal
works on this machine and is rechecked after migration, although the documentation only makes
an explicit guarantee for individual skill-entry symlinks.

Official discovery references: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[Codex skills](https://learn.chatgpt.com/docs/build-skills),
[Codex hooks](https://learn.chatgpt.com/docs/hooks),
[Claude instructions](https://code.claude.com/docs/en/memory), and
[Claude skills](https://code.claude.com/docs/en/skills),
[Claude settings](https://code.claude.com/docs/en/settings), and
[Claude hooks](https://code.claude.com/docs/en/hooks).

### Safe migration from `~/.agent` to `~/.agents`

Preview first; this is read-only:

```sh
bash scripts/setup-ai.sh
```

The content and structure scan can take about a minute with roughly 3,000 installed skill
directories.

The preview:

- fails before migration if `~/.agents`, `~/.claude`, or `~/.codex` is a folded Stow link into
  this repository, preventing runtime writes from landing in Git;
- rejects source-package entries outside the documented shared files and client adapters, so
  Git-ignored runtime state cannot be linked by Stow;
- hashes paths, contents, link targets, and executable state for valid top-level skills, then
  reports identical, singular-only, plural-only, and conflicting names;
- plans copies for singular-only skills without overwriting canonical entries, resolving a
  top-level skill link into a real directory while preserving links inside the skill;
- excludes repository-managed language skills from generic copying;
- preserves same-name/different-content conflicts in both roots;
- simulates Stow for `ai`, `claude`, and `codex`;
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
- `session-report` gives evidence-grounded prompt/context feedback and includes usage only
  when a client already exposes authoritative metadata.
- `language-warmup` is manually invokable and is injected by supported startup hooks when the
  per-machine marker exists.
- `english-teacher` and `german-teacher` retain their complete teaching references while
  keeping progress under neutral, untracked state paths.
- The authoritative English rubric applies a client-agnostic response gate: scores below 55
  defer non-urgent work until a corrected rewrite, while urgent operational and protective
  responses remain available at every score.

If a sandbox cannot write language state, the skills request scoped approval or return a
copyable update. They never weaken a client's sandbox globally.

## Shell helpers

- `k` aliases `kubectl`.
- `klocal` and `kdev` switch the default kubeconfig to their named contexts, then optionally
  run a command.
- `ksandbox` points `KUBECONFIG` at a separate sandbox file for the session.
- `kprod` always passes an explicit production context and asks for `yes` before mutating verbs.
- `reload` restarts the current shell with `exec zsh -l`.
- `docker` and `docker-compose` map to `nerdctl` and `nerdctl compose`.
- `skills` lists every skill in `~/.agents/skills`; `skills <term>` filters names and
  descriptions; `skills -d [term]` includes descriptions. Override the root with `SKILLS_DIR`.

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
AI migration and stows `ai`, `claude`, and `codex`. It does not install, authenticate, or
choose a default AI vendor. If neither client is installed, its configuration remains ready
for later use.

On an existing machine, run `bash scripts/setup-ai.sh` separately before bootstrap so the
live AI impact can be reviewed in isolation.

## Optional client setup

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
bash -n bootstrap.sh scripts/setup-ai.sh
zsh -n zsh/.aliases
jq empty claude/.claude/settings.json codex/.codex/hooks.json
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
