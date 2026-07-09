#!/usr/bin/env bash
# Idempotent new-machine setup. Safe to re-run anytime.
#   ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

# 1. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this session (Apple Silicon default prefix).
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 2. Packages from the Brewfile (stow, kubectl, colima, ghostty, ...)
brew bundle --file=./Brewfile

# 3. oh-my-zsh + the one custom plugin .zshrc loads (zsh-autosuggestions).
#    Unattended: don't switch shell or launch zsh here.
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# 4. Symlink every package into $HOME. stow is idempotent for already-linked
#    packages; it refuses to clobber pre-existing real files (move them first).
stow -t "$HOME" zsh git ghostty vim yazi claude

cat <<'EOF'

Bootstrap complete. Next steps (manual, one-time):
  colima start --runtime containerd
  mkdir -p ~/.local/bin && colima nerdctl install --path ~/.local/bin/nerdctl

Then start a fresh shell:  exec zsh -l
EOF
