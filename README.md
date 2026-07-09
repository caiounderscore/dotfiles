# Dotfiles

A normal, browsable git repo. Real files live here in `~/dotfiles/`, organized into
packages by tool; [GNU Stow](https://www.gnu.org/software/stow/) symlinks each package's
files into place in `$HOME`. Editing a symlinked file (e.g. `~/.zshrc`) edits the real
file here directly, since it's a symlink back to this repo.

## Layout

```
dotfiles/
├── zsh/
│   ├── .zshrc
│   ├── .aliases
│   └── .exports
├── git/
│   └── .gitconfig       — identity (dev@caiounderscore.xyz) + aliases
├── ghostty/
│   └── Library/Application Support/com.mitchellh.ghostty/config
├── vim/
│   └── .vimrc           — syntax highlighting on
├── yazi/
│   └── .config/yazi/yazi.toml   — always show hidden files
├── claude/
│   └── .claude/commands/session-report.md   — /session-report slash command
├── Brewfile             — `brew bundle` package list (stow, kubectl, colima, ghostty, …)
└── bootstrap.sh         — idempotent new-machine setup
```

Each top-level directory is a Stow "package" — its contents mirror the paths they should
have relative to `$HOME`.

## `.aliases` contents

- `k` → `kubectl`
- `reload` → `exec zsh -l`, restarts the shell session from scratch
- `docker` → `nerdctl`, `docker-compose` → `nerdctl compose` — drop-in Docker CLI
  compatibility on top of Colima (see "Containers" below)
- `skills [-d] <term>` → searches `~/.agents/skills/*/SKILL.md` frontmatter (name +
  description) and prints matching skill names, highlighting the matched term. Add `-d`
  to also print each match's description. Override the search directory per-machine with
  `SKILLS_DIR`. No-ops quietly if the directory doesn't exist.

## Containers (Colima + nerdctl)

No Docker Desktop — containers run through [Colima](https://github.com/abiosoft/colima)
(a Lima-based Linux VM) using `containerd` as the runtime, driven via
[nerdctl](https://github.com/containerd/nerdctl). `nerdctl` has a built-in `compose`
subcommand, so no separate `docker-compose` binary is needed.

```sh
# 1. Install (Brewfile below)
brew bundle --file=~/dotfiles/Brewfile

# 2. Start the VM with the containerd runtime
colima start --runtime containerd

# 3. One-time per machine: install a `nerdctl` alias script that talks to
#    Colima's containerd socket, without touching /usr/local/bin (no sudo needed)
mkdir -p ~/.local/bin
colima nerdctl install --path ~/.local/bin/nerdctl
```

Colima is started manually (`colima start`) rather than as a login service — stop it
with `colima stop` when you're done. `docker`/`docker-compose` in `.aliases` then just
work against it.

## `claude/` contents

Portable Claude Code config so the agent behaves the same on every machine (same
profile, same model/effort, same slash commands) instead of falling back to generic
defaults:

- `.claude/CLAUDE.md` → global profile: role, answer preferences (trade-offs, challenge
  assumptions, production-oriented), ADR conventions, and language-coaching rules.
- `.claude/settings.json` → `model`, `effortLevel=high`, and the `statusLine` (needs `jq`,
  in the Brewfile). These drive how thorough/assertive the agent is, independent of
  `CLAUDE.md`.
- `.claude/hooks/lang-warmup.sh` → the bilingual (English/German) SessionStart warm-up.
- `.claude/settings.local.json.example` → template that wires the warm-up hook in. The
  hook is **not** in the shared `settings.json` — it's opt-in per machine (see below).
- `.claude/commands/session-report.md`, `reload.md` → the `/session-report` and `/reload`
  slash commands.

## Daily use

```sh
cd ~/dotfiles
# edit files directly — they're symlinked into $HOME already
git add zsh/.zshrc
git commit -m "tweak zsh"
git push
```

To add a new package, create a directory here mirroring the target path, then:

```sh
stow -d ~/dotfiles -t "$HOME" <package-name>
```

## Set up on a new machine

```sh
git clone git@github.com:<you>/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` is idempotent (safe to re-run). It installs Homebrew if missing, runs the
Brewfile, installs oh-my-zsh + the `zsh-autosuggestions` plugin that `.zshrc` expects, and
stows every package. Then finish containers manually:

```sh
colima start --runtime containerd
mkdir -p ~/.local/bin
colima nerdctl install --path ~/.local/bin/nerdctl
```

If a target file already exists (e.g. a fresh macOS install's default `.zshrc`), move or
remove it first — `stow` refuses to overwrite existing files, only broken symlinks.

## Per-machine / work overrides

Shared config lives in the repo; anything machine- or employer-specific stays **untracked**
(`.example` templates are provided and version-controlled):

- **`~/.zshrc.local`** — sourced last by `.zshrc`. Proxy, corp `PATH`, work `KUBECONFIG`,
  etc. Copy from `zsh/.zshrc.local.example`.
- **`~/.gitconfig-work`** — work git identity. Auto-activated for any repo under `~/work/`
  via an `includeIf` rule in `.gitconfig`, so work commits use your work email while
  everything else stays personal. Copy from `git/.gitconfig-work.example`.
- **`~/.claude/settings.local.json`** — enables the bilingual warm-up on this machine.
  Copy from `claude/.claude/settings.local.json.example` on personal machines; leave it
  out on the work laptop. If the file already exists (e.g. permissions), merge in the
  `hooks` block rather than overwriting.
