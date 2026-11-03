#!/usr/bin/env zsh

set -u

readonly REPO_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-session-test.XXXXXX")"
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

mock_bin="$TEST_ROOT/bin"
mkdir -p -- "$mock_bin"

cat > "$mock_bin/codex" <<'MOCK_CODEX'
#!/bin/sh
set -eu

printf '%s\n' "$*" > "$AI_CLIENT_TEST_LOG"
MOCK_CODEX

chmod +x "$mock_bin/codex"
export PATH="$mock_bin:$PATH"
export AI_CLIENT_TEST_LOG="$TEST_ROOT/client.log"

# shellcheck disable=SC1091
source "$REPO_DIR/zsh/.aliases"

codex --resume
if [[ "$OSTYPE" == darwin* ]]; then
  [[ "$(<"$AI_CLIENT_TEST_LOG")" == "--enable prevent_idle_sleep --resume" ]] ||
    fail "codex did not enable turn-scoped sleep prevention or preserve its arguments"
else
  [[ "$(<"$AI_CLIENT_TEST_LOG")" == "--resume" ]] ||
    fail "codex arguments were not preserved on a non-macOS host"
fi

print -- 'Codex sleep-prevention tests passed'
