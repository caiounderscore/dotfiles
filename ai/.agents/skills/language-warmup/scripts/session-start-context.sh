#!/usr/bin/env bash
set -Eeuo pipefail

readonly WARMUP_MARKER="${LANGUAGE_WARMUP_MARKER:-${HOME:?HOME must be set}/.agents/state/language/warmup-enabled}"
[[ -f "$WARMUP_MARKER" ]] || exit 0

payload=$(cat)
event_source=""

if command -v jq >/dev/null 2>&1; then
  event_source=$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null) || exit 0
else
  exit 0
fi

case "$event_source" in
  startup|clear) ;;
  *) exit 0 ;;
esac

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Apply the shared `language-warmup` skill now, before handling the pending request. Follow its neutral state paths, correction rules, and sandbox-safe fallback exactly."}}
JSON
