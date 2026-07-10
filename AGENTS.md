# Dotfiles Repository Instructions

## Package Layout

- Each top-level tool directory is a GNU Stow package whose contents mirror `$HOME`.
- `ai/` owns shared personal instructions and portable user-authored skills.
- `claude/` and `codex/` are thin client adapters; keep model, UI, hook, permission, and sandbox settings client-specific.
- Runtime state belongs outside Git under client directories or `~/.agents/state/`.

## Scope

- Read `README.md`, `bootstrap.sh`, relevant package files, and `git diff` before editing.
- Keep changes minimal and preserve unrelated dirty work.
- Do not install, authenticate, choose, commit, or push for an AI vendor unless explicitly requested.

## Targeted Validation

```sh
git diff --check
bash -n bootstrap.sh scripts/setup-ai.sh
zsh -n zsh/.aliases
jq empty claude/.claude/settings.json codex/.codex/hooks.json
bash scripts/test-ai-config.sh
```

- Run ShellCheck on changed shell scripts when installed.
- Run `bash scripts/setup-ai.sh` for a read-only migration and Stow preview before `--apply`.
- Use `stow --simulate --verbose` before changing live links.
- Validate only affected packages and paths; do not run networked agent sessions solely for verification.

## Stow Safety

- Derive the repository path from the script location; never assume `~/dotfiles`.
- Never use `stow --adopt`, `rm -rf`, or overwrite a live file blindly.
- Back up a live file or symlink before replacement and show the planned impact first.
- Keep `~/.codex/skills/.system` and both legacy skill roots intact.

## Secrets and State

- Never track auth, tokens, histories, sessions, caches, databases, telemetry, generated logs, language logs, or hook-trust state.
- Treat project-local `settings.local.json`, work identities, and machine-specific paths as untracked data.
- Inspect diffs for credentials and personal runtime content before staging.

## Commit Attribution

- Do not commit unless explicitly asked.
- When attribution is requested, use the acting agent's truthful name and byline; never hard-code a specific vendor, model, or another agent's identity here.
