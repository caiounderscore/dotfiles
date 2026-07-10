---
name: reload
description: Refresh the agent's working context from current instructions, relevant state, and repository files without discarding the conversation. Use when the user asks to reload, refresh stale context, or re-check project state.
---

# Reload Context

This is a state-freshness check, not a process restart or conversation recap.

1. Re-discover and read the instruction files currently applicable to the working directory, following the active client's documented precedence. Do not assume a vendor-specific filename.
2. Re-read only task-relevant memory or state already exposed by the client. Treat client memory as optional and never crawl histories, transcripts, sessions, or caches.
3. Refresh repository state relevant to the conversation: at minimum `git status`, the latest commit when useful, and files discussed during the session that may have changed outside the agent's edits.
4. Compare the refreshed evidence with current assumptions.
5. Report briefly what was re-read, what changed, and which stale assumptions were corrected. If nothing changed, say so plainly.

Do not mutate files during the refresh. A client-native reload feature may be used when available, but is never required for this workflow.
