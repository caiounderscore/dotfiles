# From the repository root: brew bundle --file="$PWD/Brewfile"
# Source of truth for the tools these dotfiles assume exist.
# lima is pulled in automatically as colima's dependency.

# Dotfile plumbing
brew "stow"

# Shell / editor / file manager referenced by the configs
brew "vim"
brew "yazi"
brew "nvm"
brew "fzf"
brew "tuicr"

# Kubernetes CLI (aliased to `k`)
brew "kubectl"

# `watch` replacement with execution history + diffs (see the watch() wrapper
# in zsh/.aliases). Optional: the wrapper falls back to procps watch without it.
brew "hwatch"

# Used by the Claude Code statusLine command
brew "jq"

# Go toolchain used by the enabled Claude Code gopls plugin
brew "go"
brew "gopls"

# Containers without Docker Desktop (see README "Containers")
brew "colima"

# Terminal
cask "ghostty"
cask "font-jetbrains-mono-nerd-font"
