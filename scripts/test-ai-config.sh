#!/usr/bin/env bash
# Purpose: regression-test setup-ai.sh and the shared language hook without
# touching the real HOME. Every scenario runs in a disposable fixture tree.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_REPO="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly SETUP_SCRIPT="$SOURCE_REPO/scripts/setup-ai.sh"
readonly HOOK_SCRIPT="$SOURCE_REPO/ai/.agents/skills/language-warmup/scripts/session-start-context.sh"
readonly ENGLISH_RUBRIC="$SOURCE_REPO/ai/.agents/skills/english-teacher/references/scoring-rubric.md"

for command_name in awk cmp cp find jq join shasum sort stow; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'test-ai-config: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

TEST_ROOT=$(mktemp -d /tmp/dotfiles-ai-config.XXXXXX)
readonly TEST_ROOT
readonly FIXTURE_REPO="$TEST_ROOT/repo"

cleanup() {
  rm -r -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok %s - %s: %s\n' "$TEST_NUMBER" "$CURRENT_TEST" "$*" >&2
  exit 1
}

dump_log() {
  local log_file="$1"

  [[ -f "$log_file" ]] || return 0
  awk '{ print "  | " $0 }' "$log_file" >&2
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  [[ "$actual" == "$expected" ]] || \
    fail "$description (expected '$expected', got '$actual')"
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local description="$3"

  awk -v needle="$needle" '
    index($0, needle) { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$path" || fail "$description"
}

assert_absent() {
  local path="$1"
  local description="$2"

  [[ ! -e "$path" && ! -L "$path" ]] || fail "$description"
}

write_skill() {
  local directory="$1"
  local name="$2"
  local description="$3"

  mkdir -p -- "$directory"
  printf '%s\n' \
    '---' \
    "name: $name" \
    "description: $description" \
    '---' >"$directory/SKILL.md"
}

run_setup_apply() {
  local home_dir="$1"
  local log_file="$2"
  local test_locale="${3:-}"

  if [[ -n "$test_locale" ]]; then
    if ! LC_ALL="$test_locale" HOME="$home_dir" \
      bash "$FIXTURE_REPO/scripts/setup-ai.sh" --apply >"$log_file" 2>&1; then
      dump_log "$log_file"
      fail "setup-ai --apply failed with LC_ALL=$test_locale"
    fi
  elif ! HOME="$home_dir" \
    bash "$FIXTURE_REPO/scripts/setup-ai.sh" --apply >"$log_file" 2>&1; then
    dump_log "$log_file"
    fail "setup-ai --apply failed"
  fi
}

count_paths() {
  awk 'END { print NR + 0 }'
}

tree_hash() {
  local root="$1"

  (
    cd -- "$root"
    {
      find . -type f -exec shasum -a 256 {} + | awk '{ print "F\t" $0 }'
      find . -type l -exec sh -c '
        for entry do
          printf "L\t%s\t%s\n" "$entry" "$(readlink "$entry")"
        done
      ' sh {} +
      find . -type f -exec sh -c '
        for entry do
          if [ -x "$entry" ]; then
            printf "X\t1\t%s\n" "$entry"
          else
            printf "X\t0\t%s\n" "$entry"
          fi
        done
      ' sh {} +
      find . -type d -print | awk '{ print "D\t" $0 }'
    } | LC_ALL=C sort
  ) | shasum -a 256 | awk '{ print $1 }'
}

choose_non_c_locale() {
  local available=""
  local candidate

  command -v locale >/dev/null 2>&1 || {
    printf 'C\n'
    return 0
  }
  available=$(locale -a 2>/dev/null) || {
    printf 'C\n'
    return 0
  }

  for candidate in pt_BR.UTF-8 en_US.UTF-8 de_DE.UTF-8; do
    if printf '%s\n' "$available" | awk -v wanted="$candidate" '
      $0 == wanted { found = 1 }
      END { exit(found ? 0 : 1) }
    '; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$available" | awk '
    $0 != "C" && $0 != "POSIX" && $0 !~ /^C\./ { print; exit }
  '
}

prepare_fixture_repo() {
  mkdir -p -- "$FIXTURE_REPO/scripts"
  cp -pR -- \
    "$SOURCE_REPO/ai" \
    "$SOURCE_REPO/claude" \
    "$SOURCE_REPO/codex" \
    "$SOURCE_REPO/openclaude" \
    "$SOURCE_REPO/opencode" \
    "$FIXTURE_REPO/"
  cp -p -- "$SETUP_SCRIPT" "$FIXTURE_REPO/scripts/setup-ai.sh"

  # A fresh checkout has no directory after the last tracked command is removed.
  if [[ -d "$FIXTURE_REPO/claude/.claude/commands" ]]; then
    rmdir -- "$FIXTURE_REPO/claude/.claude/commands" || \
      fail "fixture's obsolete Claude commands directory is not empty"
  fi
}

test_empty_home_idempotency() {
  local home_dir="$TEST_ROOT/homes/empty"
  local physical_home
  local backup_count=0
  local agent

  mkdir -p -- "$home_dir"
  run_setup_apply "$home_dir" "$TEST_ROOT/empty-first.log"
  run_setup_apply "$home_dir" "$TEST_ROOT/empty-second.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ -L "$physical_home/.claude/skills" ]] || \
    fail "Claude skills was not linked"
  assert_eq \
    "$physical_home/.agents/skills" \
    "$(readlink "$physical_home/.claude/skills")" \
    "Claude skills link did not use the physical HOME path"
  # A folded agents link would let /agents write runtime definitions into Git.
  [[ -d "$physical_home/.claude/agents" && ! -L "$physical_home/.claude/agents" ]] || \
    fail "Claude agents directory was folded or not created"
  for agent in implementer validator verifier; do
    [[ "$physical_home/.claude/agents/$agent.md" \
      -ef "$FIXTURE_REPO_PHYSICAL/claude/.claude/agents/$agent.md" ]] || \
      fail "Claude $agent agent was not linked"
  done
  [[ -d "$physical_home/.codex/agents" && ! -L "$physical_home/.codex/agents" ]] || \
    fail "Codex agents directory was folded or not created"
  for agent in platform-lens security-lens reliability-lens; do
    [[ "$physical_home/.codex/agents/$agent.toml" \
      -ef "$FIXTURE_REPO_PHYSICAL/codex/.codex/agents/$agent.toml" ]] || \
      fail "Codex $agent agent was not linked"
  done
  [[ -f "$physical_home/.claude/settings.json" && ! -L "$physical_home/.claude/settings.json" ]] || \
    fail "Claude settings.json was not seeded as a machine-local file"
  cmp -s "$FIXTURE_REPO_PHYSICAL/claude/.claude/settings.json" \
    "$physical_home/.claude/settings.json" || \
    fail "seeded Claude settings.json differs from the tracked baseline"
  [[ -f "$physical_home/.codex/hooks.json" && ! -L "$physical_home/.codex/hooks.json" ]] || \
    fail "Codex hooks.json was not seeded as a machine-local file"
  cmp -s "$FIXTURE_REPO_PHYSICAL/codex/.codex/hooks.json" \
    "$physical_home/.codex/hooks.json" || \
    fail "seeded Codex hooks.json differs from the tracked baseline"
  [[ -L "$physical_home/.agent/skills" ]] || \
    fail "legacy singular skill root was not linked"
  assert_eq \
    "$physical_home/.agents/skills" \
    "$(readlink "$physical_home/.agent/skills")" \
    "legacy singular skill root did not use the canonical physical path"
  [[ "$physical_home/.agents/skills/reload/SKILL.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/ai/.agents/skills/reload/SKILL.md" ]] || \
    fail "known shared reload skill did not resolve to its canonical source"
  [[ "$physical_home/.agents/skills/tuicr-review/SKILL.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/ai/.agents/skills/tuicr-review/SKILL.md" ]] || \
    fail "shared tuicr-review skill did not resolve to its canonical source"
  [[ -L "$physical_home/.codex/skills/tuicr-review" ]] || \
    fail "Codex tuicr-review adapter was not linked"
  [[ "$physical_home/.codex/skills/tuicr-review/SKILL.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/ai/.agents/skills/tuicr-review/SKILL.md" ]] || \
    fail "Codex tuicr-review adapter did not resolve to its canonical source"
  [[ -L "$physical_home/.openclaude/CLAUDE.md" ]] || \
    fail "OpenClaude instructions adapter was not linked"
  [[ "$physical_home/.openclaude/CLAUDE.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/openclaude/.openclaude/CLAUDE.md" ]] || \
    fail "OpenClaude instructions adapter is not the tracked CLAUDE.md adapter"
  [[ -L "$physical_home/.config/opencode/AGENTS.md" ]] || \
    fail "opencode instructions adapter was not linked"
  [[ "$physical_home/.config/opencode/AGENTS.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/ai/.agents/AGENTS.md" ]] || \
    fail "opencode instructions adapter is not the canonical AGENTS.md"
  assert_contains \
    "$TEST_ROOT/empty-second.log" \
    "Claude skill root already resolves to $physical_home/.agents/skills" \
    "second apply did not recognize the existing Claude skills link"
  assert_contains \
    "$TEST_ROOT/empty-second.log" \
    "Legacy skill root already resolves to $physical_home/.agents/skills" \
    "second apply did not recognize the unified legacy skills link"

  if [[ -d "$physical_home/.agents/state/backups" ]]; then
    backup_count=$(find "$physical_home/.agents/state/backups" \
      -mindepth 1 -maxdepth 1 -type d -print | count_paths)
  fi
  assert_eq 0 "$backup_count" "idempotent empty-home apply created a backup"
}

test_existing_claude_settings_preserved() {
  local home_dir="$TEST_ROOT/homes/existing-claude-settings"
  local config="$home_dir/.claude/settings.json"
  local original="$TEST_ROOT/claude-settings.original"
  local hooks="$home_dir/.codex/hooks.json"
  local hooks_original="$TEST_ROOT/codex-hooks.original"
  local physical_home

  mkdir -p -- "$(dirname -- "$config")" "$(dirname -- "$hooks")"
  printf '%s\n' '{' '  "model": "haiku"' '}' >"$config"
  printf '%s\n' '{' '  "hooks": {}' '}' >"$hooks"
  cp -p -- "$config" "$original"
  cp -p -- "$hooks" "$hooks_original"

  run_setup_apply "$home_dir" "$TEST_ROOT/existing-claude-first.log"
  run_setup_apply "$home_dir" "$TEST_ROOT/existing-claude-second.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ ! -L "$physical_home/.claude/settings.json" ]] || \
    fail "existing Claude settings.json was replaced by a link"
  cmp -s "$original" "$physical_home/.claude/settings.json" || \
    fail "existing Claude settings.json was changed"
  [[ ! -L "$physical_home/.codex/hooks.json" ]] || \
    fail "existing Codex hooks.json was replaced by a link"
  cmp -s "$hooks_original" "$physical_home/.codex/hooks.json" || \
    fail "existing Codex hooks.json was changed"
  [[ "$physical_home/.claude/agents/verifier.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/claude/.claude/agents/verifier.md" ]] || \
    fail "Claude agents did not coexist with the existing settings"
}

test_managed_links_become_machine_local() {
  local home_dir="$TEST_ROOT/homes/managed-links"
  local source_hash
  local physical_home
  local relative

  source_hash=$(tree_hash "$FIXTURE_REPO/codex")
  mkdir -p -- "$home_dir/.claude" "$home_dir/.codex"
  ln -s -- "$FIXTURE_REPO_PHYSICAL/claude/.claude/settings.json" "$home_dir/.claude/settings.json"
  ln -s -- "$FIXTURE_REPO_PHYSICAL/codex/.codex/hooks.json" "$home_dir/.codex/hooks.json"

  run_setup_apply "$home_dir" "$TEST_ROOT/managed-links-first.log"
  run_setup_apply "$home_dir" "$TEST_ROOT/managed-links-second.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  for relative in .claude/settings.json .codex/hooks.json; do
    [[ -f "$physical_home/$relative" && ! -L "$physical_home/$relative" ]] || \
      fail "Stow link $relative was not replaced with a machine-local copy"
  done
  cmp -s "$FIXTURE_REPO_PHYSICAL/claude/.claude/settings.json" "$physical_home/.claude/settings.json" || \
    fail "converted Claude settings.json differs from the tracked file"
  cmp -s "$FIXTURE_REPO_PHYSICAL/codex/.codex/hooks.json" "$physical_home/.codex/hooks.json" || \
    fail "converted Codex hooks.json differs from the tracked file"
  assert_eq "$source_hash" "$(tree_hash "$FIXTURE_REPO/codex")" \
    "link conversion changed the tracked Codex package"
}

test_existing_openclaude_config_preserved() {
  local home_dir="$TEST_ROOT/homes/existing-openclaude-config"
  local config="$home_dir/.openclaude/settings.json"
  local original="$TEST_ROOT/openclaude-settings.original"
  local physical_home

  mkdir -p -- "$(dirname -- "$config")"
  printf '%s\n' \
    '{' \
    '  "env": {},' \
    '  "model": "gpt-5.4"' \
    '}' >"$config"
  cp -p -- "$config" "$original"

  run_setup_apply "$home_dir" "$TEST_ROOT/existing-openclaude-first.log"
  run_setup_apply "$home_dir" "$TEST_ROOT/existing-openclaude-second.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ -d "$physical_home/.openclaude" && ! -L "$physical_home/.openclaude" ]] || \
    fail "existing .openclaude directory was folded or replaced"
  cmp -s "$original" "$physical_home/.openclaude/settings.json" || \
    fail "existing OpenClaude settings.json was changed"
  [[ "$physical_home/.openclaude/CLAUDE.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/openclaude/.openclaude/CLAUDE.md" ]] || \
    fail "OpenClaude adapter did not coexist with the existing config"
}

test_existing_opencode_config_preserved() {
  local home_dir="$TEST_ROOT/homes/existing-opencode-config"
  local config="$home_dir/.config/opencode/opencode.jsonc"
  local original="$TEST_ROOT/opencode.jsonc.original"
  local physical_home

  mkdir -p -- "$(dirname -- "$config")"
  # The JSON key is intentionally literal, not a shell variable.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '{' \
    '  "$schema": "https://opencode.ai/config.json",' \
    '  // Client-specific settings must remain machine-local.' \
    '  "share": "disabled"' \
    '}' >"$config"
  cp -p -- "$config" "$original"

  run_setup_apply "$home_dir" "$TEST_ROOT/existing-opencode-first.log"
  run_setup_apply "$home_dir" "$TEST_ROOT/existing-opencode-second.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ -d "$physical_home/.config" && ! -L "$physical_home/.config" ]] || \
    fail "existing .config directory was folded or replaced"
  [[ -d "$physical_home/.config/opencode" && ! -L "$physical_home/.config/opencode" ]] || \
    fail "existing opencode config directory was folded or replaced"
  cmp -s "$original" "$physical_home/.config/opencode/opencode.jsonc" || \
    fail "existing opencode.jsonc was changed"
  [[ "$physical_home/.config/opencode/AGENTS.md" \
    -ef "$FIXTURE_REPO_PHYSICAL/ai/.agents/AGENTS.md" ]] || \
    fail "opencode adapter did not coexist with the existing config"
}

test_singular_skill_copy() {
  local home_dir="$TEST_ROOT/homes/singular-skills"
  local physical_home
  local real_source="$home_dir/.agent/skills/real-skill"
  local linked_source="$TEST_ROOT/external/linked-skill"
  local legacy_backup
  local real_target
  local linked_target

  mkdir -p -- "$home_dir/.agent/skills" "$linked_source/scripts"
  write_skill "$real_source" real-skill "real legacy skill"
  printf '%s\n' '#!/usr/bin/env bash' 'printf real' >"$real_source/run.sh"
  chmod 755 "$real_source/run.sh"

  write_skill "$linked_source" linked-skill "linked legacy skill"
  printf '%s\n' '#!/usr/bin/env bash' 'printf linked' >"$linked_source/scripts/run.sh"
  chmod 755 "$linked_source/scripts/run.sh"
  ln -s -- SKILL.md "$linked_source/skill-link.md"
  ln -s -- "$linked_source" "$home_dir/.agent/skills/linked-skill"

  run_setup_apply "$home_dir" "$TEST_ROOT/singular-skills.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)
  real_target="$physical_home/.agents/skills/real-skill"
  linked_target="$physical_home/.agents/skills/linked-skill"

  [[ -d "$real_target" && ! -L "$real_target" ]] || \
    fail "real singular-only skill was not copied as a directory"
  [[ -d "$linked_target" && ! -L "$linked_target" ]] || \
    fail "top-level skill symlink was not resolved into a real directory"
  cmp -s "$real_source/SKILL.md" "$real_target/SKILL.md" || \
    fail "real singular-only skill content changed during copy"
  cmp -s "$linked_source/SKILL.md" "$linked_target/SKILL.md" || \
    fail "linked singular-only skill content changed during copy"
  [[ -x "$linked_source/scripts/run.sh" && -x "$linked_target/scripts/run.sh" ]] || \
    fail "linked skill executable state was not preserved"
  assert_eq SKILL.md "$(readlink "$linked_target/skill-link.md")" \
    "link inside a resolved skill was not preserved"
  [[ -L "$home_dir/.agent/skills" ]] || \
    fail "legacy skill root was not unified with the canonical root"
  [[ "$home_dir/.agent/skills" -ef "$physical_home/.agents/skills" ]] || \
    fail "legacy skill root does not resolve to the canonical root"
  legacy_backup=$(find "$physical_home/.agents/state/backups" \
    -path '*/legacy-agent/skills' -type d -print)
  [[ -n "$legacy_backup" && -L "$legacy_backup/linked-skill" ]] || \
    fail "legacy top-level skill symlink was not preserved in the backup"
}

test_skill_conflicts_with_locale() {
  local home_dir="$TEST_ROOT/homes/skill-conflicts"
  local singular="$home_dir/.agent/skills"
  local plural="$home_dir/.agents/skills"
  local test_locale
  local empty_entry_count
  local legacy_backup

  write_skill "$singular/content-conflict" content-conflict "singular content"
  write_skill "$plural/content-conflict" content-conflict "plural content"
  write_skill "$singular/mode-conflict" mode-conflict "same content"
  write_skill "$plural/mode-conflict" mode-conflict "same content"
  write_skill "$singular/structural-conflict" structural-conflict "same content"
  write_skill "$plural/structural-conflict" structural-conflict "same content"
  mkdir -p -- "$singular/structural-conflict/required-empty"
  write_skill "$singular/z" z "C-sorted singular-only skill"
  write_skill "$singular/á" á "shared non-ASCII skill"
  write_skill "$plural/á" á "shared non-ASCII skill"
  printf '%s\n' '#!/usr/bin/env bash' 'printf same' >"$singular/mode-conflict/run.sh"
  cp -p -- "$singular/mode-conflict/run.sh" "$plural/mode-conflict/run.sh"
  chmod 700 "$singular/mode-conflict/run.sh"
  chmod 600 "$plural/mode-conflict/run.sh"

  test_locale=$(choose_non_c_locale)
  [[ -n "$test_locale" ]] || test_locale=C
  if [[ "$test_locale" == C ]]; then
    printf '# non-C locale unavailable; conflict test is using C\n'
  else
    printf '# conflict test locale: %s\n' "$test_locale"
  fi
  run_setup_apply "$home_dir" "$TEST_ROOT/skill-conflicts.log" "$test_locale"

  assert_contains "$TEST_ROOT/skill-conflicts.log" "same-name conflicts: 3" \
    "content, executable-mode, and structural conflicts were not all reported"
  assert_contains "$TEST_ROOT/skill-conflicts.log" "shared identical: 1" \
    "non-C join did not recognize the shared non-ASCII skill"
  assert_contains "$TEST_ROOT/skill-conflicts.log" "singular-only: 1" \
    "non-C join did not recognize the C-sorted singular-only skill"
  assert_contains "$TEST_ROOT/skill-conflicts.log" \
    "Claude will use the canonical plural-root version of each conflicting skill" \
    "active-root behavior for conflicting skills was not reported"
  legacy_backup=$(find "$home_dir/.agents/state/backups" \
    -path '*/legacy-agent/skills' -type d -print)
  [[ -n "$legacy_backup" ]] || fail "legacy conflict root was not backed up"
  assert_contains "$legacy_backup/content-conflict/SKILL.md" "singular content" \
    "singular content conflict was not preserved in the backup"
  assert_contains "$plural/content-conflict/SKILL.md" "plural content" \
    "plural content conflict was overwritten"
  [[ -x "$legacy_backup/mode-conflict/run.sh" ]] || \
    fail "singular executable-mode conflict lost its executable state"
  [[ ! -x "$plural/mode-conflict/run.sh" ]] || \
    fail "plural executable-mode conflict gained executable state"
  [[ -d "$legacy_backup/structural-conflict/required-empty" ]] || \
    fail "singular empty directory was removed from the structural conflict"
  empty_entry_count=$(find "$legacy_backup/structural-conflict/required-empty" \
    -mindepth 1 -print | count_paths)
  assert_eq 0 "$empty_entry_count" \
    "singular required directory no longer remained empty"
  assert_absent "$plural/structural-conflict/required-empty" \
    "plural structural conflict gained the singular-only directory"
}

test_language_log_migration() {
  local home_dir="$TEST_ROOT/homes/language-logs"
  local physical_home
  local language_state
  local conflicts
  local english_source="$home_dir/.claude/english-mistakes-log.md"
  local english_target="$home_dir/.agents/state/language/english-mistakes-log.md"
  local german_source="$home_dir/.claude/german-mistakes-log.md"
  local german_teacher_source="$home_dir/.claude/german-teacher-mistakes-log.md"
  local german_conflict
  local german_teacher_conflict
  local conflict_count

  mkdir -p -- "$home_dir/.claude" "$(dirname -- "$english_target")"
  printf '%s\n' 'same English history' >"$english_source"
  cp -p -- "$english_source" "$english_target"
  printf '%s\n' 'German history one' >"$german_source"
  printf '%s\n' 'German history two' >"$german_teacher_source"

  run_setup_apply "$home_dir" "$TEST_ROOT/language-logs.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)
  language_state="$physical_home/.agents/state/language"
  conflicts="$language_state/migration-conflicts"

  cmp -s "$english_source" "$language_state/english-mistakes-log.md" || \
    fail "identical English history was changed"
  assert_absent "$language_state/german-mistakes-log.md" \
    "divergent German histories produced a canonical file"
  conflict_count=$(find "$conflicts" -type f -name 'german-*.md' -print | count_paths)
  assert_eq 2 "$conflict_count" "German conflict migration did not preserve two files"
  german_conflict=$(find "$conflicts" -type f -name 'german-mistakes-log.*.md' -print)
  german_teacher_conflict=$(find "$conflicts" -type f -name 'german-teacher-mistakes-log.*.md' -print)
  cmp -s "$german_source" "$german_conflict" || \
    fail "first German conflict content changed"
  cmp -s "$german_teacher_source" "$german_teacher_conflict" || \
    fail "second German conflict content changed"
  assert_contains "$TEST_ROOT/language-logs.log" "Language log already migrated" \
    "identical English history was not recognized"
  assert_contains "$TEST_ROOT/language-logs.log" "Divergent sources found" \
    "divergent German history was not reported"
}

test_folded_command_retirement() {
  local home_dir="$TEST_ROOT/homes/folded-commands"
  local physical_home
  local managed="$FIXTURE_REPO_PHYSICAL/claude/.claude/commands"
  local backup
  local backup_count

  mkdir -p -- "$home_dir/.claude"
  ln -s -- "$managed" "$home_dir/.claude/commands"
  run_setup_apply "$home_dir" "$TEST_ROOT/folded-commands.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  assert_absent "$physical_home/.claude/commands" \
    "folded legacy commands link was not retired"
  backup_count=$(find "$physical_home/.agents/state/backups" \
    -type l -path '*/claude/commands' -print | count_paths)
  assert_eq 1 "$backup_count" "folded commands link backup count is wrong"
  backup=$(find "$physical_home/.agents/state/backups" \
    -type l -path '*/claude/commands' -print)
  assert_eq "$managed" "$(readlink "$backup")" \
    "folded commands backup did not preserve its link target"
}

test_per_file_command_retirement() {
  local home_dir="$TEST_ROOT/homes/per-file-commands"
  local physical_home
  local commands="$home_dir/.claude/commands"
  local managed="$FIXTURE_REPO_PHYSICAL/claude/.claude/commands"
  local unrelated_target="$TEST_ROOT/external/custom-command.md"
  local backup_count

  mkdir -p -- "$commands" "$(dirname -- "$unrelated_target")"
  printf '%s\n' 'keep regular command' >"$commands/keep.md"
  printf '%s\n' 'keep linked command' >"$unrelated_target"
  ln -s -- "$unrelated_target" "$commands/custom.md"
  ln -s -- "$managed/reload.md" "$commands/reload.md"
  ln -s -- "$managed/../commands/session-report.md" "$commands/session-report.md"

  run_setup_apply "$home_dir" "$TEST_ROOT/per-file-commands.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)
  commands="$physical_home/.claude/commands"

  [[ -d "$commands" && ! -L "$commands" ]] || \
    fail "per-file commands directory was replaced"
  assert_absent "$commands/reload.md" "managed reload command link was not retired"
  assert_absent "$commands/session-report.md" \
    "managed session-report command link was not retired"
  assert_contains "$commands/keep.md" "keep regular command" \
    "unrelated regular command was changed"
  assert_eq "$unrelated_target" "$(readlink "$commands/custom.md")" \
    "unrelated command symlink was changed"
  backup_count=$(find "$physical_home/.agents/state/backups" \
    -type l -path '*/claude/commands/*.md' -print | count_paths)
  assert_eq 2 "$backup_count" "per-file managed command backup count is wrong"
}

test_real_claude_skills_refusal() {
  local home_dir="$TEST_ROOT/homes/real-claude-skills"
  local physical_home
  local log_file="$TEST_ROOT/real-claude-skills.log"

  mkdir -p -- "$home_dir/.claude/skills"
  printf '%s\n' sentinel >"$home_dir/.claude/skills/sentinel"
  if HOME="$home_dir" bash "$FIXTURE_REPO/scripts/setup-ai.sh" --apply \
    >"$log_file" 2>&1; then
    fail "setup succeeded despite a real Claude skills directory"
  fi
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ -d "$physical_home/.claude/skills" && ! -L "$physical_home/.claude/skills" ]] || \
    fail "real Claude skills directory was replaced"
  assert_contains "$physical_home/.claude/skills/sentinel" sentinel \
    "real Claude skills directory content was changed"
  assert_contains "$log_file" "refusing to replace it automatically" \
    "real Claude skills refusal was not reported"
  assert_absent "$physical_home/.agents/AGENTS.md" \
    "Stow was applied after the Claude skills refusal"
}

test_warmup_marker_migration() {
  local home_dir="$TEST_ROOT/homes/warmup-marker"
  local physical_home
  local settings="$home_dir/.claude/settings.local.json"
  local original="$TEST_ROOT/settings.local.original.json"

  mkdir -p -- "$(dirname -- "$settings")"
  printf '%s\n' \
    '{' \
    '  "permissions": {"allow": ["Read"]},' \
    '  "hooks": {' \
    '    "SessionStart": [{' \
    '      "hooks": [{' \
    '        "type": "command",' \
    '        "command": "bash \"$HOME/.claude/hooks/lang-warmup.sh\""' \
    '      }]' \
    '    }]' \
    '  }' \
    '}' >"$settings"
  cp -p -- "$settings" "$original"

  run_setup_apply "$home_dir" "$TEST_ROOT/warmup-marker.log"
  physical_home=$(cd -- "$home_dir" && pwd -P)

  [[ -f "$physical_home/.agents/state/language/warmup-enabled" ]] || \
    fail "legacy warm-up preference did not create the neutral marker"
  cmp -s "$original" "$physical_home/.claude/settings.local.json" || \
    fail "legacy settings.local.json was changed"
  assert_contains "$TEST_ROOT/warmup-marker.log" \
    "Preserved the per-machine warm-up preference" \
    "warm-up marker migration was not reported"
}

test_hook_gating() {
  local home_dir="$TEST_ROOT/homes/hooks"
  local marker="$home_dir/.agents/state/language/warmup-enabled"
  local absent_marker="$home_dir/.agents/state/language/disabled"
  local output

  mkdir -p -- "$(dirname -- "$marker")"
  : >"$marker"

  if ! output=$(printf '%s' '{"source":"startup"}' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$marker" bash "$HOOK_SCRIPT"); then
    fail "startup hook failed"
  fi
  printf '%s\n' "$output" | jq -e '
    .hookSpecificOutput.hookEventName == "SessionStart" and
    (.hookSpecificOutput.additionalContext | contains("language-warmup")) and
    (.hookSpecificOutput.additionalContext |
      contains("~/.agents/skills/language-warmup/SKILL.md")) and
    (.hookSpecificOutput.additionalContext |
      contains("catalog omission alone does not mean that the skill is unavailable"))
  ' >/dev/null || fail "startup hook output was not valid injection JSON"

  if ! output=$(printf '%s' '{"source":"clear"}' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$marker" \
    bash "$SOURCE_REPO/claude/.claude/hooks/lang-warmup.sh"); then
    fail "clear hook failed through the Claude adapter"
  fi
  printf '%s\n' "$output" | jq -e \
    '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null || \
    fail "clear hook output was not valid injection JSON"

  if ! output=$(printf '%s' '{"source":"resume"}' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$marker" bash "$HOOK_SCRIPT"); then
    fail "resume hook failed"
  fi
  assert_eq "" "$output" "resume hook was not silent"

  if ! output=$(printf '%s' '{"source":"compact"}' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$marker" \
    bash "$SOURCE_REPO/codex/.codex/hooks/lang-warmup.sh"); then
    fail "compact hook failed through the Codex adapter"
  fi
  assert_eq "" "$output" "compact hook was not silent"

  if ! output=$(printf '%s' 'not-json' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$marker" bash "$HOOK_SCRIPT"); then
    fail "invalid JSON hook input returned failure"
  fi
  assert_eq "" "$output" "invalid JSON hook input was not silent"

  if ! output=$(printf '%s' '{"source":"startup"}' | \
    HOME="$home_dir" LANGUAGE_WARMUP_MARKER="$absent_marker" bash "$HOOK_SCRIPT"); then
    fail "absent-marker hook returned failure"
  fi
  assert_eq "" "$output" "hook ran without the warm-up marker"
}

test_session_health() {
  local script="$SOURCE_REPO/claude/.claude/hooks/session-health.sh"
  local dir="$TEST_ROOT/session-health"
  local small='{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":40000}}}'
  local manual='{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual"}}'
  local auto='{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto"}}'
  local output
  export SESSION_HEALTH_COMPACT_WINDOW=300000

  mkdir -p -- "$dir"
  printf '%s\n' "$small" >"$dir/small.jsonl"
  printf '%s\n' "$manual" "$manual" \
    '{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":5000,"cache_read_input_tokens":160000}}}' \
    >"$dir/warn.jsonl"
  printf '%s\n' "$auto" \
    '{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_creation_input_tokens":5000,"cache_read_input_tokens":255000}}}' \
    >"$dir/crit.jsonl"
  printf '%s\n' "$auto" "$small" >"$dir/auto.jsonl"
  printf '%s\n' "$manual" "$small" >"$dir/manual.jsonl"
  printf '%s\n' "$manual" "$manual" "$small" >"$dir/manual-twice.jsonl"

  status() { jq -nc --arg t "$1" '{transcript_path:$t,model:{display_name:"Opus"},workspace:{current_dir:"/w"}}' | bash "$script" statusline; }
  compact() { jq -nc --arg t "$1" --arg s "${2:-compact}" '{source:$s,transcript_path:$t}' | bash "$script" compact; }

  assert_eq "Opus | /w | ctx 41k·13%" "$(status "$dir/small.jsonl")" \
    "healthy status line was wrong"
  output=$(status "$dir/warn.jsonl")
  [[ "$output" == *"⚠ ctx 165k·55% · 2× · /compact at boundary"* ]] ||
    fail "session past the smart zone was not flagged: $output"
  output=$(status "$dir/crit.jsonl")
  [[ "$output" == *"⛔ ctx 260k·86% · 1× (1 auto) · /compact now"* ]] ||
    fail "session near auto-compact was not flagged critical: $output"

  assert_eq "Opus | /w | ctx 41k·13% · 1×" "$(status "$dir/manual.jsonl")" \
    "one manual compaction should stay healthy"
  output=$(status "$dir/manual-twice.jsonl")
  [[ "$output" == *"⚠ ctx 41k·13% · 2×"* ]] ||
    fail "two manual compactions were not flagged: $output"

  assert_eq "" "$(compact "$dir/manual.jsonl")" "compact hook warned after one manual compaction"
  compact "$dir/manual-twice.jsonl" | jq -e '.systemMessage | contains("Compacted 2× (0 auto)")' >/dev/null ||
    fail "compact hook did not count manual compactions"
  assert_eq "" "$(compact "$dir/auto.jsonl" startup)" "compact hook ran on a non-compact start"
  compact "$dir/auto.jsonl" | jq -e '
    (.systemMessage | contains("Compacted 1× (1 auto)")) and
    .hookSpecificOutput.hookEventName == "SessionStart" and
    (.hookSpecificOutput.additionalContext | contains("next phase boundary"))
  ' >/dev/null || fail "compact hook did not warn after an automatic compaction"
  compact "$dir/crit.jsonl" | jq -e '.hookSpecificOutput.additionalContext | contains("then stop")' >/dev/null ||
    fail "critical compact hook did not ask to stop"

  printf 'not-json' | bash "$script" statusline >/dev/null || fail "status line failed on invalid input"
  unset SESSION_HEALTH_COMPACT_WINDOW
}

test_managed_workspace_hook_context() {
  local home_dir="$TEST_ROOT/homes/workspace-hook"
  local outer_workspace="$TEST_ROOT/workspaces/outer"
  local inner_workspace="$outer_workspace/inner"
  local session_dir="$inner_workspace/repository/subdirectory"
  local output

  mkdir -p -- "$home_dir" "$session_dir"
  outer_workspace=$(cd -- "$outer_workspace" && pwd -P)
  inner_workspace=$(cd -- "$inner_workspace" && pwd -P)
  session_dir=$(cd -- "$session_dir" && pwd -P)
  jq -n \
    --arg goal "Outer goal" \
    --arg root "$outer_workspace" \
    '{workspace: "outer", goal: $goal, sourceBranch: "main", root: $root, repositories: []}' \
    >"$outer_workspace/.task-workspace.json"
  jq -n \
    --arg goal "Nearest goal" \
    --arg root "$inner_workspace" \
    '{workspace: "inner", goal: $goal, sourceBranch: "main", root: $root, repositories: []}' \
    >"$inner_workspace/.task-workspace.json"

  if ! output=$(jq -n --arg cwd "$session_dir" '{source: "startup", cwd: $cwd}' | \
    HOME="$home_dir" bash "$HOOK_SCRIPT"); then
    fail "managed workspace hook failed"
  fi
  printf '%s\n' "$output" | jq -e \
    --arg root "$inner_workspace" \
    --arg outer "$outer_workspace" '
      .hookSpecificOutput.hookEventName == "SessionStart" and
      (.hookSpecificOutput.additionalContext | contains("This is a managed task workspace.")) and
      (.hookSpecificOutput.additionalContext | contains("Nearest goal")) and
      (.hookSpecificOutput.additionalContext | contains($root + "/AGENTS.md")) and
      (.hookSpecificOutput.additionalContext | contains("Use only the canonical worktrees")) and
      (.hookSpecificOutput.additionalContext | contains("creating another clone")) and
      (.hookSpecificOutput.additionalContext | contains("Outer goal") | not) and
      (.hookSpecificOutput.additionalContext | contains($outer + "/AGENTS.md") | not)
    ' >/dev/null || fail "hook did not inject the nearest managed workspace context"
}

test_language_response_gate_contract() {
  assert_contains "$ENGLISH_RUBRIC" \
    '| 80–100 | Handle the request normally and append English Notes with concise tips.' \
    "English rubric did not define the normal-response tier"
  assert_contains "$ENGLISH_RUBRIC" \
    '| 55–79 | Handle the request normally, append English Notes, and label the category mini-drills as `Required practice`.' \
    "English rubric did not define the required-practice tier"
  assert_contains "$ENGLISH_RUBRIC" \
    '| Below 55 | Do not perform or substantially answer a non-urgent request yet.' \
    "English rubric did not define the below-55 rewrite gate"
  assert_contains "$ENGLISH_RUBRIC" \
    'active incidents, production degradation, outages' \
    "English rubric did not preserve urgent operational responses"
  assert_contains "$ENGLISH_RUBRIC" \
    'clarification or refusal needed to avoid an unsafe, destructive, or unauthorized action' \
    "English rubric did not preserve protective responses"
  assert_contains "$SOURCE_REPO/ai/.agents/AGENTS.md" \
    "the rubric's response gate" \
    "shared instructions did not reference the authoritative response gate"
  assert_contains "$SOURCE_REPO/ai/.agents/skills/language-warmup/SKILL.md" \
    'when the gate defers a non-urgent pending request' \
    "language warm-up did not honor the response gate"
}

test_folded_claude_root_preflight() {
  local home_dir="$TEST_ROOT/homes/folded-claude-root"
  local physical_home
  local package="$FIXTURE_REPO_PHYSICAL/claude/.claude"
  local sentinel="$package/history.jsonl"
  local sentinel_copy="$TEST_ROOT/folded-root-sentinel.original"
  local log_file="$TEST_ROOT/folded-claude-root.log"
  local link_target
  local package_hash

  mkdir -p -- "$home_dir"
  printf '%s\n' '{"runtime":"must remain outside Git"}' >"$sentinel"
  cp -p -- "$sentinel" "$sentinel_copy"
  ln -s -- "$package" "$home_dir/.claude"
  physical_home=$(cd -- "$home_dir" && pwd -P)
  link_target=$(readlink "$physical_home/.claude")
  package_hash=$(tree_hash "$package")

  if HOME="$home_dir" bash "$FIXTURE_REPO/scripts/setup-ai.sh" --apply \
    >"$log_file" 2>&1; then
    fail "setup succeeded with a folded Claude package root"
  fi

  [[ -L "$physical_home/.claude" ]] || \
    fail "folded Claude root symlink was replaced"
  assert_eq "$link_target" "$(readlink "$physical_home/.claude")" \
    "folded Claude root link target changed"
  cmp -s "$sentinel_copy" "$sentinel" || \
    fail "runtime sentinel in the Claude package changed"
  assert_eq "$package_hash" "$(tree_hash "$package")" \
    "fixture Claude package changed after preflight refusal"
  assert_absent "$physical_home/.agents" \
    "neutral HOME state was created before folded-root refusal"
  assert_contains "$log_file" "is a folded Stow link into the Claude package" \
    "folded Claude root warning was not reported"
  assert_contains "$log_file" \
    "Refusing to write through it because that would place runtime state in Git" \
    "folded Claude root safety reason was not reported"
}

test_unexpected_package_source_preflight() {
  local home_dir="$TEST_ROOT/homes/unexpected-package-source"
  local physical_home
  local package="$FIXTURE_REPO_PHYSICAL/claude/.claude"
  local sentinel="$package/history.jsonl"
  local sentinel_copy="$TEST_ROOT/folded-root-sentinel.original"
  local log_file="$TEST_ROOT/unexpected-package-source.log"
  local package_hash

  mkdir -p -- "$home_dir"
  [[ -f "$sentinel" ]] || fail "runtime sentinel from the folded-root fixture is missing"
  package_hash=$(tree_hash "$package")
  physical_home=$(cd -- "$home_dir" && pwd -P)

  if HOME="$home_dir" bash "$FIXTURE_REPO/scripts/setup-ai.sh" --apply \
    >"$log_file" 2>&1; then
    fail "setup succeeded with unexpected Claude package content"
  fi

  cmp -s "$sentinel_copy" "$sentinel" || \
    fail "unexpected package-source preflight changed the runtime sentinel"
  assert_eq "$package_hash" "$(tree_hash "$package")" \
    "unexpected package-source preflight changed the fixture package"
  assert_absent "$physical_home/.agents" \
    "neutral HOME state was created before source allowlist refusal"
  assert_contains "$log_file" \
    "Unexpected entry in the claude Stow package: $sentinel" \
    "unexpected Claude package entry warning was not reported"
  assert_contains "$log_file" \
    "Refusing to Stow package content outside the managed adapter allowlist" \
    "source allowlist refusal was not reported"
}

TEST_NUMBER=0
CURRENT_TEST=setup
prepare_fixture_repo
readonly FIXTURE_REPO_PHYSICAL="$(cd -- "$FIXTURE_REPO" && pwd -P)"

run_test() {
  local description="$1"
  local test_function="$2"

  TEST_NUMBER=$((TEST_NUMBER + 1))
  CURRENT_TEST="$description"
  "$test_function"
  printf 'ok %s - %s\n' "$TEST_NUMBER" "$description"
}

run_test "empty HOME apply is physically idempotent" test_empty_home_idempotency
run_test "existing Claude settings and Codex hooks are preserved" test_existing_claude_settings_preserved
run_test "Stow links to machine-local files become copies" test_managed_links_become_machine_local
run_test "existing OpenClaude config is preserved" test_existing_openclaude_config_preserved
run_test "existing opencode config is preserved" test_existing_opencode_config_preserved
run_test "singular-only real and linked skills copy safely" test_singular_skill_copy
run_test "content, mode, and structural conflicts survive locale changes" test_skill_conflicts_with_locale
run_test "identical English and divergent German logs migrate safely" test_language_log_migration
run_test "folded legacy Claude commands link is retired" test_folded_command_retirement
run_test "per-file Claude command links retire selectively" test_per_file_command_retirement
run_test "real Claude skills directory is refused" test_real_claude_skills_refusal
run_test "legacy warm-up preference migrates to a marker" test_warmup_marker_migration
run_test "warm-up hook is marker and event gated" test_hook_gating
run_test "session health flags long sessions in the status line and after compaction" test_session_health
run_test "session hook injects the nearest managed workspace contract" test_managed_workspace_hook_context
run_test "English response gate preserves urgent and protective work" test_language_response_gate_contract
run_test "folded Claude root is refused before migration" test_folded_claude_root_preflight
run_test "unexpected Stow package content is refused" test_unexpected_package_source_preflight

printf '1..%s\n' "$TEST_NUMBER"
