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
│   └── .aliases
├── git/
│   └── .gitconfig       — identity (dev@caiounderscore.xyz) + aliases
└── ghostty/
    └── Library/Application Support/com.mitchellh.ghostty/config   — theme = Terminal Basic Dark
```

Each top-level directory is a Stow "package" — its contents mirror the paths they should
have relative to `$HOME`.

## `.aliases` contents

- `k` → `kubectl`
- `skills [-d] <term>` → searches `~/.agents/skills/*/SKILL.md` frontmatter (name +
  description) and prints matching skill names, highlighting the matched term. Add `-d`
  to also print each match's description. Override the search directory per-machine with
  `SKILLS_DIR`. No-ops quietly if the directory doesn't exist.

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
stow -t "$HOME" zsh git ghostty
```

If a target file already exists (e.g. a fresh macOS install's default `.zshrc`), move or
remove it first — `stow` refuses to overwrite existing files, only broken symlinks.
