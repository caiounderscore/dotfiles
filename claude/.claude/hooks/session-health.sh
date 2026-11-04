#!/usr/bin/env bash
# Session health for Claude Code. `statusline` prints model, directory, context size, how full the
# auto-compact window is, and the automatic compactions so far. `compact` runs as a SessionStart hook
# after an automatic compaction and asks for the phase-boundary decision.
# Thresholds follow Matt Pocock's ask-matt skill: past the ~150k smart zone, decide at the next phase
# boundary; an automatic compaction lands mid-phase and loses the thread, so its approach is critical.
set -uo pipefail

mode="${1:-statusline}"
payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

# shortcut: ignores per-model /autocompact overrides in modelSettings; upgrade if you set those.
window="${SESSION_HEALTH_COMPACT_WINDOW:-$(jq -r '.autoCompactWindow // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
[[ "$window" =~ ^[1-9][0-9]*$ ]] || window=967000 # Claude Code's default auto-compact point on 1M models
readonly WARN_TOKENS="${SESSION_HEALTH_WARN_TOKENS:-150000}"
readonly CRIT_TOKENS="${SESSION_HEALTH_CRIT_TOKENS:-$(( window * 85 / 100 ))}"
readonly WARN_AUTO_COMPACTIONS="${SESSION_HEALTH_WARN_AUTO_COMPACTIONS:-1}"
readonly CRIT_AUTO_COMPACTIONS="${SESSION_HEALTH_CRIT_AUTO_COMPACTIONS:-2}"

transcript=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null) || transcript=""
auto=0
last_trigger=""
tokens=0
if [[ -n "$transcript" && -f "$transcript" ]]; then
  # Manual /compact at a phase boundary is the intended use; only automatic ones count.
  boundaries=$(grep '"subtype":"compact_boundary"' "$transcript" 2>/dev/null)
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
(( tokens >= WARN_TOKENS || auto >= WARN_AUTO_COMPACTIONS )) && level=warn
(( tokens >= CRIT_TOKENS || auto >= CRIT_AUTO_COMPACTIONS )) && level=crit

case "$mode" in
  statusline)
    model=$(jq -r '.model.display_name // "Claude"' <<<"$payload" 2>/dev/null) || model="Claude"
    dir=$(jq -r '.workspace.current_dir // empty' <<<"$payload" 2>/dev/null) || dir=""
    health="ctx $(( tokens / 1000 ))k ($(( tokens * 100 / window ))% of auto-compact) · ${auto}× auto-compact"
    case "$level" in
      warn) health=$'\033[33m⚠ '"$health"' · past smart zone'$'\033[0m' ;;
      crit) health=$'\033[31m⛔ '"$health"' · /compact or /clear at phase boundary'$'\033[0m' ;;
    esac
    printf '%s | %s | %s\n' "$model" "${dir/#$HOME/~}" "$health"
    ;;
  compact)
    [[ "$(jq -r '.source // empty' <<<"$payload" 2>/dev/null)" == "compact" && "$last_trigger" == "auto" ]] || exit 0
    action="At the next phase boundary, propose one move in this order: continue if the next phase needs this context and fits the smart zone; /clear if it is disposable; a subagent if the task runs unattended; otherwise /compact with a focus."
    [[ "$level" == crit ]] && action="Finish the action in progress, record the state in the ticket, then stop and ask me to choose between /clear and /compact with a focus; continue only if I tell you to."
    jq -n --arg n "$auto" --arg action "$action" '{
      systemMessage: "⚠ Auto-compacted \($n)× mid-phase. Earlier decisions now survive only as summaries.",
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "This session was compacted automatically \($n) times, so earlier decisions survive only as summaries. Start your next reply with a quoted line beginning \"> ⚠ Auto-compacted \($n)×:\". \($action)"
      }
    }'
    ;;
esac
exit 0
