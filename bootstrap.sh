#!/usr/bin/env bash
# Idempotent new-machine setup. Safe to re-run anytime.
#   ./bootstrap.sh
set -Eeuo pipefail

readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$REPO_DIR"

# 1. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this session on Apple Silicon or Intel macOS.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# 2. Packages from the Brewfile (stow, kubectl, colima, ghostty, ...)
brew bundle --file="$REPO_DIR/Brewfile"

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

# 4. Preview, then link the existing non-AI packages.
readonly -a BASE_PACKAGES=(zsh git ghostty vim yazi tuicr)
stow --simulate --verbose=2 \
  --dir="$REPO_DIR" --target="$HOME" "${BASE_PACKAGES[@]}"
stow --verbose=1 \
  --dir="$REPO_DIR" --target="$HOME" "${BASE_PACKAGES[@]}"

# 5. Inventory/migrate the legacy skill root and language state, then preview
#    and stow the neutral ai package plus the Claude and Codex adapters.
bash "$REPO_DIR/scripts/setup-ai.sh" --apply

cat <<'EOF'

Bootstrap complete. Next steps (manual, one-time):
  colima start --runtime containerd
  mkdir -p ~/.local/bin && colima nerdctl install --path ~/.local/bin/nerdctl

Then start a fresh shell:  exec zsh -l
EOF
