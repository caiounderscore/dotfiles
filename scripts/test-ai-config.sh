#!/usr/bin/env bash
# Purpose: regression-test setup-ai.sh and the shared language hook without
# touching the real HOME. Every scenario runs in a disposable fixture tree.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_REPO="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly SETUP_SCRIPT="$SOURCE_REPO/scripts/setup-ai.sh"
readonly HOOK_SCRIPT="$SOURCE_REPO/ai/.agents/skills/language-warmup/scripts/session-start-context.sh"

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
  assert_contains \
    "$TEST_ROOT/empty-second.log" \
    "Claude skill root already resolves to $physical_home/.agents/skills" \
    "second apply did not recognize the existing Claude skills link"

  if [[ -d "$physical_home/.agents/state/backups" ]]; then
    backup_count=$(find "$physical_home/.agents/state/backups" \
      -mindepth 1 -maxdepth 1 -type d -print | count_paths)
  fi
  assert_eq 0 "$backup_count" "idempotent empty-home apply created a backup"
}

test_singular_skill_copy() {
  local home_dir="$TEST_ROOT/homes/singular-skills"
  local physical_home
  local real_source="$home_dir/.agent/skills/real-skill"
  local linked_source="$TEST_ROOT/external/linked-skill"
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
  [[ -L "$home_dir/.agent/skills/linked-skill" ]] || \
    fail "legacy top-level skill symlink was modified"
}

test_skill_conflicts_with_locale() {
  local home_dir="$TEST_ROOT/homes/skill-conflicts"
  local singular="$home_dir/.agent/skills"
  local plural="$home_dir/.agents/skills"
  local test_locale
  local empty_entry_count

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
  assert_contains "$singular/content-conflict/SKILL.md" "singular content" \
    "singular content conflict was overwritten"
  assert_contains "$plural/content-conflict/SKILL.md" "plural content" \
    "plural content conflict was overwritten"
  [[ -x "$singular/mode-conflict/run.sh" ]] || \
    fail "singular executable-mode conflict lost its executable state"
  [[ ! -x "$plural/mode-conflict/run.sh" ]] || \
    fail "plural executable-mode conflict gained executable state"
  [[ -d "$singular/structural-conflict/required-empty" ]] || \
    fail "singular empty directory was removed from the structural conflict"
  empty_entry_count=$(find "$singular/structural-conflict/required-empty" \
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
    (.hookSpecificOutput.additionalContext | contains("language-warmup"))
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
run_test "singular-only real and linked skills copy safely" test_singular_skill_copy
run_test "content, mode, and structural conflicts survive locale changes" test_skill_conflicts_with_locale
run_test "identical English and divergent German logs migrate safely" test_language_log_migration
run_test "folded legacy Claude commands link is retired" test_folded_command_retirement
run_test "per-file Claude command links retire selectively" test_per_file_command_retirement
run_test "real Claude skills directory is refused" test_real_claude_skills_refusal
run_test "legacy warm-up preference migrates to a marker" test_warmup_marker_migration
run_test "warm-up hook is marker and event gated" test_hook_gating
run_test "folded Claude root is refused before migration" test_folded_claude_root_preflight
run_test "unexpected Stow package content is refused" test_unexpected_package_source_preflight

printf '1..%s\n' "$TEST_NUMBER"
