#!/usr/bin/env bash
# Mandatory bilingual (German A2–B1 / English B2–C1) session warm-up.
# Fires only on a genuinely new session (startup) or cleared context (clear);
# stays silent on resume/compact so it never interrupts ongoing work.
source=$(cat | jq -r '.source // "startup"' 2>/dev/null || echo startup)
case "$source" in
  startup|clear) ;;            # proceed: emit the warm-up
  *) exit 0 ;;                 # resume/compact/etc: no warm-up
esac
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"MANDATORY SESSION WARM-UP (do this before anything else, no skip). Caio is studying German (target A2 to B1) and English (target B2 to C1). At the very start of this session, before his actual request: (1) greet in one short line; (2) ask EXACTLY ONE German question at A2 to B1 level AND ONE English question at B2 to C1 level — vary them each session and prefer his logged weak points; (3) wait for his answers; (4) correct both with the rising-bar approach — mark errors, name the category, give the natural correct form, then update the logs at ~/.claude/english-mistakes-log.md and the german-teacher mistakes log (repeated logged errors cap the score at 85); (5) only then continue with whatever he asked. Keep it concise: two short questions. This warm-up is mandatory and cannot be skipped. Follow the /english-teacher and /german-teacher conventions."}}
JSON
