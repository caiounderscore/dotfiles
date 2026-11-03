#!/usr/bin/env zsh

set -u
setopt pipe_fail

readonly REPO_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-review-test.XXXXXX")"
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Resolved from this script's physical repository path.
# shellcheck disable=SC1091
source "$REPO_DIR/zsh/.aliases"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_file_contains() {
  local file="$1" expected="$2"
  grep -F -- "$expected" "$file" >/dev/null ||
    fail "expected $file to contain: $expected"
}

assert_line_count() {
  local file="$1" expected="$2" actual
  actual=$(wc -l < "$file" | tr -d ' ')
  [[ "$actual" == "$expected" ]] ||
    fail "expected $file to contain $expected lines, got $actual"
}

create_repo() {
  local repo_path="$1" branch="${2:-main}"
  mkdir -p -- "$repo_path"
  git -C "$repo_path" init -q -b "$branch" || fail "could not initialize $repo_path"
  git -C "$repo_path" config user.name "Review Test"
  git -C "$repo_path" config user.email "review-test@example.invalid"
  print -- initial > "$repo_path/tracked.txt"
  git -C "$repo_path" add tracked.txt
  git -C "$repo_path" commit -qm initial || fail "could not commit in $repo_path"
}

setup_mocks() {
  local case_root="$1"
  local mock_dir="$case_root/bin"
  mkdir -p -- "$mock_dir"

  cat > "$mock_dir/fzf" <<'MOCK_FZF'
#!/bin/sh
set -u

input=$(cat)
iteration=1
if [ -f "$FZF_STATE" ]; then
  iteration=$(($(cat "$FZF_STATE") + 1))
fi
printf '%s\n' "$iteration" > "$FZF_STATE"
printf '%s\n%s\n' "--- selection $iteration ---" "$input" >> "$FZF_LOG"
printf '%s\n' "$*" >> "$FZF_ARGS_LOG"

choice=$(sed -n "${iteration}p" "$FZF_PLAN")
[ "$choice" != CANCEL ] || exit 130
printf '%s\n' "$input" | awk -v repository="$choice" '
  $1 == repository { print; found = 1; exit }
  END { if (!found) exit 1 }
'
MOCK_FZF

  cat > "$mock_dir/tuicr" <<'MOCK_TUICR'
#!/bin/sh
set -u

iteration=1
if [ -f "$TUICR_STATE" ]; then
  iteration=$(($(cat "$TUICR_STATE") + 1))
fi
printf '%s\n' "$iteration" > "$TUICR_STATE"
printf '%s\t%s\n' "$PWD" "$*" >> "$TUICR_LOG"

action=$(sed -n "${iteration}p" "$TUICR_PLAN")
case "$action" in
  clean) rm -f -- dirty.txt ;;
  fail) exit 7 ;;
esac
MOCK_TUICR

  chmod +x "$mock_dir/fzf" "$mock_dir/tuicr"
  export PATH="$mock_dir:$ORIGINAL_PATH"
  export FZF_PLAN="$case_root/fzf-plan"
  export FZF_STATE="$case_root/fzf-state"
  export FZF_LOG="$case_root/fzf.log"
  export FZF_ARGS_LOG="$case_root/fzf-args.log"
  export TUICR_PLAN="$case_root/tuicr-plan"
  export TUICR_STATE="$case_root/tuicr-state"
  export TUICR_LOG="$case_root/tuicr.log"
  : > "$FZF_LOG"
  : > "$FZF_ARGS_LOG"
  : > "$TUICR_LOG"
}

run_review() {
  local workspace="$1" output="$2"
  shift 2
  local caller exit_status

  cd -- "$workspace" || fail "could not enter $workspace"
  caller="${PWD:A}"
  review "$@" > "$output" 2>&1
  exit_status=$?
  [[ "${PWD:A}" == "$caller" ]] || fail "review changed the caller directory"
  cd -- "$TEST_ROOT" || fail "could not restore test root"
  return "$exit_status"
}

readonly ORIGINAL_PATH="$PATH"

# Multiple clean repositories can be reviewed in one invocation; cancellation
# exits cleanly, no non-repository child appears, and caller cwd is preserved.
case_root="$TEST_ROOT/multiple"
workspace="$case_root/workspace with spaces"
mkdir -p -- "$workspace/not-a-repository"
create_repo "$workspace/repo-a"
create_repo "$workspace/repo-b"
setup_mocks "$case_root"
printf '%s\n' repo-a repo-b CANCEL > "$FZF_PLAN"
printf '%s\n' success success > "$TUICR_PLAN"
run_review "$workspace" "$case_root/output" || fail "multiple-repository review failed"
assert_line_count "$TUICR_LOG" 2
assert_file_contains "$TUICR_LOG" "${workspace:A}/repo-a"
assert_file_contains "$TUICR_LOG" "${workspace:A}/repo-b"
assert_file_contains "$FZF_ARGS_LOG" "Select repository to review · Esc to exit"
if grep -F -- "not-a-repository" "$FZF_LOG" >/dev/null; then
  fail "review listed a non-repository child"
fi

# Metadata is rebuilt after tuicr exits: a dirty repository launches with -w,
# then appears clean on the next selector pass after the mock removes its file.
case_root="$TEST_ROOT/refresh"
workspace="$case_root/workspace"
create_repo "$workspace/repo-a"
print -- dirty > "$workspace/repo-a/dirty.txt"
setup_mocks "$case_root"
printf '%s\n' repo-a CANCEL > "$FZF_PLAN"
printf '%s\n' clean > "$TUICR_PLAN"
run_review "$workspace" "$case_root/output" || fail "metadata refresh review failed"
assert_file_contains "$TUICR_LOG" $'repo-a\t-w'
assert_file_contains "$FZF_LOG" "repo-a                   1 changes"
assert_file_contains "$FZF_LOG" "repo-a                   clean"

# A range is validated independently for every selected repository. A missing
# base in repo-b reports a repository-specific error and returns to selection.
case_root="$TEST_ROOT/range"
workspace="$case_root/workspace"
create_repo "$workspace/repo-a"
git -C "$workspace/repo-a" checkout -qb feature
print -- feature >> "$workspace/repo-a/tracked.txt"
git -C "$workspace/repo-a" commit -qam feature
create_repo "$workspace/repo-b" feature
setup_mocks "$case_root"
printf '%s\n' repo-a repo-b repo-a CANCEL > "$FZF_PLAN"
printf '%s\n' success success > "$TUICR_PLAN"
run_review "$workspace" "$case_root/output" main..HEAD || fail "two-dot range review failed"
assert_line_count "$TUICR_LOG" 2
assert_file_contains "$TUICR_LOG" $'repo-a\t-r main..HEAD'
assert_file_contains "$case_root/output" "review: repo-b: base revision is not a commit: main"

# Three-dot ranges remain unchanged across selections.
setup_mocks "$case_root/three-dot"
printf '%s\n' repo-a CANCEL > "$FZF_PLAN"
printf '%s\n' success > "$TUICR_PLAN"
run_review "$workspace" "$case_root/three-dot/output" main...HEAD || fail "three-dot range review failed"
assert_file_contains "$TUICR_LOG" $'repo-a\t-r main...HEAD'

# A non-zero tuicr exit is reported, then the selector opens again and another
# repository can be reviewed.
case_root="$TEST_ROOT/nonzero"
workspace="$case_root/workspace"
create_repo "$workspace/repo-a"
create_repo "$workspace/repo-b"
setup_mocks "$case_root"
printf '%s\n' repo-a repo-b CANCEL > "$FZF_PLAN"
printf '%s\n' fail success > "$TUICR_PLAN"
run_review "$workspace" "$case_root/output" || fail "non-zero tuicr ended review"
assert_line_count "$TUICR_LOG" 2
assert_file_contains "$case_root/output" "review: tuicr exited with status 7 for repo-a"

# A one-repository workspace still works through a legacy symlink. Nested Git
# repositories remain excluded, and detached HEAD metadata is preserved.
case_root="$TEST_ROOT/symlink"
workspace="$case_root/workspace"
external_repo="$case_root/external/repository"
mkdir -p -- "$workspace/container"
create_repo "$external_repo"
git -C "$external_repo" checkout -q --detach HEAD
create_repo "$workspace/container/nested-repo"
ln -s -- "$external_repo" "$workspace/legacy-repo"
setup_mocks "$case_root"
printf '%s\n' legacy-repo CANCEL > "$FZF_PLAN"
printf '%s\n' success > "$TUICR_PLAN"
run_review "$workspace" "$case_root/output" || fail "one-repository symlink review failed"
assert_line_count "$TUICR_LOG" 1
assert_file_contains "$FZF_LOG" "legacy-repo"
assert_file_contains "$FZF_LOG" "detached@"
assert_file_contains "$FZF_LOG" "legacy-symlink"
if grep -F -- "nested-repo" "$FZF_LOG" >/dev/null; then
  fail "review listed a nested repository"
fi

print -- "PASS: review loop"
