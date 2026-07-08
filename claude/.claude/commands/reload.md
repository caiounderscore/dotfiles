---
description: Soft-reload context mid-session — re-read rules files, memory, and project state without clearing conversation history
---

This can't be a true process restart (that's `/clear`) — it's a context refresh:
re-read what might have gone stale during a long conversation, without losing
the conversation itself.

1. Re-read any `CLAUDE.md` (or equivalent rules file) for the current project,
   from the working directory up through its parent directories, in case it
   changed since session start.
2. Re-read `MEMORY.md` in the auto-memory directory, and re-read any specific
   memory files that are relevant to what we're currently working on.
3. Check current project state relevant to the conversation so far — e.g.
   `git status`/`git log -1` if inside a git repo, and whether any files this
   conversation has discussed have since changed on disk outside of my own
   edits.
4. Report back in a short list: what was re-read, anything that's changed
   since we started (stale assumptions to correct), and confirm you're
   working from current state. If nothing changed, say so plainly instead of
   padding the report.

Do not re-summarize the whole conversation — this is a state-freshness check,
not a recap.
