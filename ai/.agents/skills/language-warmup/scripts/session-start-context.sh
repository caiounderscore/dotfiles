#!/usr/bin/env bash
set -Eeuo pipefail

readonly WARMUP_MARKER="${LANGUAGE_WARMUP_MARKER:-${HOME:?HOME must be set}/.agents/state/language/warmup-enabled}"
payload=$(cat)
event_source=""
event_cwd=""
workspace_manifest=""
workspace_root=""
workspace_goal=""
declared_root=""
additional_context=""

if command -v jq >/dev/null 2>&1; then
  event_source=$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null) || exit 0
  event_cwd=$(printf '%s' "$payload" | \
    jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null) || exit 0
else
  exit 0
fi

case "$event_source" in
  startup|clear) ;;
  *) exit 0 ;;
esac

find_workspace_manifest() {
  local current="$1"

  [[ -d "$current" ]] || return 1
  current=$(cd -- "$current" 2>/dev/null && pwd -P) || return 1

  while :; do
    if [[ -f "$current/.task-workspace.json" &&
          ! -L "$current/.task-workspace.json" ]]; then
      printf '%s\n' "$current/.task-workspace.json"
      return 0
    fi
    [[ "$current" == "/" ]] && return 1
    current=$(dirname -- "$current")
  done
}

if [[ -z "$event_cwd" ]]; then
  event_cwd="$PWD"
fi

workspace_manifest=$(find_workspace_manifest "$event_cwd") || workspace_manifest=""
if [[ -n "$workspace_manifest" ]]; then
  workspace_root=$(dirname -- "$workspace_manifest")
  declared_root=$(jq -r '.root // empty' "$workspace_manifest" 2>/dev/null) || declared_root=""
  workspace_goal=$(jq -r \
    'if (.goal | type) == "string" then .goal else empty end' \
    "$workspace_manifest" 2>/dev/null) || workspace_goal=""

  if [[ "$declared_root" == "$workspace_root" ]]; then
    additional_context=$(printf '%s\n\n%s\n%s\n\n%s\n%s\n\n%s\n%s\n%s\n' \
      'This is a managed task workspace.' \
      'Task goal:' "${workspace_goal:-Not specified.}" \
      'Canonical workspace:' "$workspace_root" \
      "Read $workspace_root/AGENTS.md before modifying repositories." \
      'Use only the canonical worktrees declared there.' \
      'If Git prevents safe work in one of them, stop and report the blocker instead of creating another clone.')
  fi
fi

if [[ -f "$WARMUP_MARKER" ]]; then
  if [[ -n "$additional_context" ]]; then
    additional_context+=$'\n'
  fi
  # Backticks are intentional prose for the agent, not shell expressions.
  # shellcheck disable=SC2016
  additional_context+='Before handling the pending request, read and apply the shared `language-warmup` skill directly from `~/.agents/skills/language-warmup/SKILL.md`. A bounded or truncated client skill catalog may omit it; catalog omission alone does not mean that the skill is unavailable. If the neutral file cannot be read, try an available skill provider, then use the mandated sandbox-safe fallback only if neither source is accessible. Follow its neutral state paths and correction rules exactly.'
fi

[[ -n "$additional_context" ]] || exit 0

jq -n --arg additional_context "$additional_context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $additional_context
  }
}'
