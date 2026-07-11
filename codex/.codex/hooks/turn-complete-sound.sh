#!/usr/bin/env bash
set -euo pipefail

readonly payload="${1:-}"

# Codex currently invokes `notify` only for agent-turn-complete, but keep the
# filter explicit so future notification types do not unexpectedly make noise.
if [ -z "$payload" ] || ! jq -e '.type == "agent-turn-complete"' \
  >/dev/null 2>&1 <<<"$payload"; then
  exit 0
fi

# Detach playback so the notification helper does not delay the next prompt.
/usr/bin/nohup /usr/bin/afplay -v 0.35 \
  /System/Library/Sounds/Glass.aiff \
  </dev/null >/dev/null 2>&1 &
