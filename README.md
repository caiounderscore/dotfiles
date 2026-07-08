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
└── claude/
    └── .claude/commands/
        ├── session-report.md   — /session-report slash command
        └── reload.md           — /reload slash command
```

Each top-level directory is a Stow "package" — its contents mirror the paths they should
have relative to `$HOME`.

## `.aliases` contents

- `k` → `kubectl`
- `reload` → `exec zsh -l`, restarts the shell session from scratch
- `skills [-d] <term>` → searches `~/.agents/skills/*/SKILL.md` frontmatter (name +
  description) and prints matching skill names, highlighting the matched term. Add `-d`
  to also print each match's description. Override the search directory per-machine with
  `SKILLS_DIR`. No-ops quietly if the directory doesn't exist.

## `claude/` contents

- `.claude/commands/session-report.md` → the `/session-report` slash command. Run it at
  the end of a Claude Code session for a short, session-grounded report: concrete
  context-engineering/prompt-construction improvements (not generic advice), plus
  `/usage` output with the subscription-vs-API billing caveat spelled out.
- `.claude/commands/reload.md` → the `/reload` slash command. A custom command can't
  truly restart the process the way the terminal's `reload` alias does (that's `/clear`);
  instead this re-reads CLAUDE.md/rules files, memory, and current project state
  mid-conversation, without losing conversation history.

> Not tracked yet: a `Brewfile` (Homebrew snapshot). Add later with
> `brew bundle dump --file=$HOME/dotfiles/Brewfile` once you have packages worth pinning.

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
```

If a target file already exists (e.g. a fresh macOS install's default `.zshrc`), move or
remove it first — `stow` refuses to overwrite existing files, only broken symlinks.
