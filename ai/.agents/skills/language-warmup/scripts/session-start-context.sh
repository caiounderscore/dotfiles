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
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Before handling the pending request, read and apply the shared `language-warmup` skill directly from `~/.agents/skills/language-warmup/SKILL.md`. A bounded or truncated client skill catalog may omit it; catalog omission alone does not mean that the skill is unavailable. If the neutral file cannot be read, try an available skill provider, then use the skill's mandated sandbox-safe fallback only if neither source is accessible. Follow its neutral state paths and correction rules exactly."}}
JSON
