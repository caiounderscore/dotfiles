#!/usr/bin/env bash
# Session health for Claude Code. `statusline` prints model, directory, context size with how full the
# auto-compact window is, and the compactions so far with how many were automatic. `compact` runs as a
# SessionStart hook after a compaction and asks for the phase-boundary decision.
# Thresholds follow Matt Pocock's ask-matt skill: past the ~150k smart zone, /compact manually at the
# next phase boundary; an automatic compaction lands mid-phase and loses the thread, and a second
# compaction of any kind leaves the oldest decisions as a summary of a summary.
set -uo pipefail

mode="${1:-statusline}"
payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

# shortcut: ignores per-model /autocompact overrides in modelSettings; upgrade if you set those.
window="${SESSION_HEALTH_COMPACT_WINDOW:-$(jq -r '.autoCompactWindow // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
[[ "$window" =~ ^[1-9][0-9]*$ ]] || window=967000 # Claude Code's default auto-compact point on 1M models
readonly WARN_TOKENS="${SESSION_HEALTH_WARN_TOKENS:-150000}"
readonly CRIT_TOKENS="${SESSION_HEALTH_CRIT_TOKENS:-$(( window * 85 / 100 ))}"
readonly WARN_COMPACTIONS="${SESSION_HEALTH_WARN_COMPACTIONS:-2}"
readonly CRIT_AUTO_COMPACTIONS="${SESSION_HEALTH_CRIT_AUTO_COMPACTIONS:-2}"

transcript=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null) || transcript=""
total=0
auto=0
last_trigger=""
tokens=0
if [[ -n "$transcript" && -f "$transcript" ]]; then
  boundaries=$(grep '"subtype":"compact_boundary"' "$transcript" 2>/dev/null)
  total=$(grep -c . <<<"$boundaries") || total=0
  auto=$(grep -c '"trigger":"auto"' <<<"$boundaries") || auto=0
  last_trigger=$(tail -n 1 <<<"$boundaries" | jq -r '.compactMetadata.trigger // empty' 2>/dev/null) || last_trigger=""
  # The last assistant turn's input is the context the model last saw.
  tokens=$(tail -c 2000000 "$transcript" | grep '"type":"assistant"' | tail -n 1 | jq -r '
    .message.usage // {} |
    (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
  ' 2>/dev/null) || tokens=0
  [[ "$tokens" =~ ^[0-9]+$ ]] || tokens=0
fi
level=ok
(( tokens >= WARN_TOKENS || total >= WARN_COMPACTIONS )) && level=warn
(( tokens >= CRIT_TOKENS || auto >= CRIT_AUTO_COMPACTIONS )) && level=crit

case "$mode" in
  statusline)
    model=$(jq -r '.model.display_name // "Claude"' <<<"$payload" 2>/dev/null) || model="Claude"
    dir=$(jq -r '.workspace.current_dir // empty' <<<"$payload" 2>/dev/null) || dir=""
    health="ctx $(( tokens / 1000 ))k·$(( tokens * 100 / window ))%"
    (( total > 0 )) && health+=" · ${total}×"
    (( auto > 0 )) && health+=" (${auto} auto)"
    advice=""
    if (( tokens >= CRIT_TOKENS )); then
      advice=" · /compact now"
    elif (( tokens >= WARN_TOKENS )); then
      advice=" · /compact at boundary"
    fi
    case "$level" in
      warn) health=$'\033[33m⚠ '"$health$advice"$'\033[0m' ;;
      crit) health=$'\033[31m⛔ '"$health$advice"$'\033[0m' ;;
    esac
    printf '%s | %s | %s\n' "$model" "${dir/#$HOME/~}" "$health"
    ;;
  compact)
    [[ "$(jq -r '.source // empty' <<<"$payload" 2>/dev/null)" == "compact" ]] || exit 0
    [[ "$last_trigger" == "auto" ]] || (( total >= WARN_COMPACTIONS )) || exit 0
    action="At the next phase boundary, propose one move in this order: continue if the next phase needs this context and fits the smart zone; /clear if it is disposable; a subagent if the task runs unattended; otherwise /compact with a focus."
    [[ "$level" == crit ]] && action="Finish the action in progress, record the state in the ticket, then stop and ask me to choose between /clear and /compact with a focus; continue only if I tell you to."
    jq -n --arg n "$total" --arg a "$auto" --arg action "$action" '{
      systemMessage: "⚠ Compacted \($n)× (\($a) auto). Earlier decisions now survive only as summaries.",
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "This session has been compacted \($n) times (\($a) automatically), so earlier decisions survive only as summaries. Start your next reply with a quoted line beginning \"> ⚠ Compacted \($n)× (\($a) auto):\". \($action)"
      }
    }'
    ;;
esac
exit 0
