#!/usr/bin/env bash
# Session health for Claude Code. `statusline` prints model, directory, context size, and
# compaction count, highlighted once the session leaves its smart zone. `compact` runs as a
# SessionStart hook after each compaction and recommends a fresh session past the threshold.
set -uo pipefail

readonly WARN_TOKENS="${SESSION_HEALTH_WARN_TOKENS:-250000}"
readonly WARN_COMPACTIONS="${SESSION_HEALTH_WARN_COMPACTIONS:-2}"
readonly CRIT_TOKENS="${SESSION_HEALTH_CRIT_TOKENS:-400000}"
readonly CRIT_COMPACTIONS="${SESSION_HEALTH_CRIT_COMPACTIONS:-4}"
mode="${1:-statusline}"
payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

transcript=$(jq -r '.transcript_path // empty' <<<"$payload" 2>/dev/null) || transcript=""
compactions=0
tokens=0
if [[ -n "$transcript" && -f "$transcript" ]]; then
  compactions=$(grep -c '"subtype":"compact_boundary"' "$transcript" 2>/dev/null) || compactions=0
  # The last assistant turn's input is the context the model last saw.
  tokens=$(tail -c 2000000 "$transcript" | grep '"type":"assistant"' | tail -n 1 | jq -r '
    .message.usage // {} |
    (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
  ' 2>/dev/null) || tokens=0
  [[ "$tokens" =~ ^[0-9]+$ ]] || tokens=0
fi
level=ok
(( tokens >= WARN_TOKENS || compactions >= WARN_COMPACTIONS )) && level=warn
(( tokens >= CRIT_TOKENS || compactions >= CRIT_COMPACTIONS )) && level=crit

case "$mode" in
  statusline)
    model=$(jq -r '.model.display_name // "Claude"' <<<"$payload" 2>/dev/null) || model="Claude"
    dir=$(jq -r '.workspace.current_dir // empty' <<<"$payload" 2>/dev/null) || dir=""
    health="ctx $(( tokens / 1000 ))k · ${compactions}× compact"
    case "$level" in
      warn) health=$'\033[33m⚠ '"$health"$'\033[0m' ;;
      crit) health=$'\033[31m⛔ '"$health"$' · abra nova sessão\033[0m' ;;
    esac
    printf '%s | %s | %s\n' "$model" "${dir/#$HOME/~}" "$health"
    ;;
  compact)
    [[ "$(jq -r '.source // empty' <<<"$payload" 2>/dev/null)" == "compact" ]] || exit 0
    (( compactions >= WARN_COMPACTIONS )) || exit 0
    action="Recommend that I record the current state (ticket comments or /handoff) and open a fresh session."
    if [[ "$level" == crit ]]; then
      action="Finish the action in progress, record the state in the ticket or with /handoff, then stop and ask me to open a fresh session; continue only if I tell you to."
    elif (( compactions > WARN_COMPACTIONS )); then
      action="Stop at the next phase boundary and propose that handoff before continuing."
    fi
    jq -n --arg n "$compactions" --arg action "$action" '{
      systemMessage: "⚠ Sessão compactada \($n)×. Decisões antigas agora existem só como resumo; considere gravar o estado e abrir uma sessão nova.",
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "This session has been compacted \($n) times, so earlier decisions survive only as summaries. Start your next reply with a quoted line beginning \"> ⚠ Sessão compactada \($n)×:\". \($action)"
      }
    }'
    ;;
esac
exit 0
