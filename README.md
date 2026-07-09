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
└── Brewfile             — `brew bundle` package list (currently: colima, kubectl)
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

## Containers + local Kubernetes (Colima + nerdctl + k3s)

No Docker Desktop — containers run through [Colima](https://github.com/abiosoft/colima)
(a Lima-based Linux VM) using `containerd` as the runtime, driven via
[nerdctl](https://github.com/containerd/nerdctl). `nerdctl` has a built-in `compose`
subcommand, so no separate `docker-compose` binary is needed. `--kubernetes` provisions
a single-node [k3s](https://k3s.io/) cluster inside the same VM for local testing.

```sh
# 1. Install (Brewfile below)
brew bundle --file=~/dotfiles/Brewfile

# 2. Start the VM: containerd runtime + a local k3s cluster
colima start --runtime containerd --kubernetes

# 3. One-time per machine: install a `nerdctl` alias script that talks to
#    Colima's containerd socket, without touching /usr/local/bin (no sudo needed)
mkdir -p ~/.local/bin
colima nerdctl install --path ~/.local/bin/nerdctl
```

Colima is started manually (`colima start`) rather than as a login service — stop it
with `colima stop` when you're done. `docker`/`docker-compose` in `.aliases` then just
work against it.

Colima writes a `colima` context into `~/.kube/config` and activates it automatically
(`kubectl config current-context` → `colima`), so `kubectl`/`k` already point at the
local cluster with no extra setup — unless/until other clusters get added to the
kubeconfig, nothing more is needed. Note: Colima always disables k3s's bundled Traefik
and swaps in its own port-forwarding cloud-controller-manager in place of
`servicelb` — CoreDNS, local-path storage, and metrics-server stay on.

## `claude/` contents

- `.claude/commands/session-report.md` → the `/session-report` slash command. Run it at
  the end of a Claude Code session for a short, session-grounded report: concrete
  context-engineering/prompt-construction improvements (not generic advice), plus
  `/usage` output with the subscription-vs-API billing caveat spelled out.

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
# 1. Install stow
brew install stow   # or your distro's package manager

# 2. Clone this repo
git clone git@github.com:<you>/dotfiles.git ~/dotfiles

# 3. Symlink every package into $HOME
cd ~/dotfiles
stow -t "$HOME" zsh git ghostty vim yazi claude

# 4. Install everything in the Brewfile (currently: colima, kubectl)
brew bundle --file=~/dotfiles/Brewfile

# 5. Set up containers + local Kubernetes — see "Containers" above
colima start --runtime containerd --kubernetes
mkdir -p ~/.local/bin
colima nerdctl install --path ~/.local/bin/nerdctl
```

If a target file already exists (e.g. a fresh macOS install's default `.zshrc`), move or
remove it first — `stow` refuses to overwrite existing files, only broken symlinks.
