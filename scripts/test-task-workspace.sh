#!/usr/bin/env bash
# Focused Git integration tests for the task-workspace zsh helper. All Git
# repositories and worktrees live under one disposable temporary root.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
SOURCE_REPO="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly SOURCE_REPO
readonly ALIASES_FILE="$SOURCE_REPO/zsh/.aliases"

for command_name in awk find git jq zsh; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'test-task-workspace: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

TEST_ROOT=$(mktemp -d /tmp/dotfiles-task-workspace.XXXXXX)
readonly TEST_ROOT
readonly TEST_HOME="$TEST_ROOT/home"
mkdir -p -- "$TEST_HOME"

cleanup() {
  if [[ "$TEST_ROOT" != /tmp/dotfiles-task-workspace.* ]]; then
    printf 'test-task-workspace: refusing unsafe cleanup path: %s\n' "$TEST_ROOT" >&2
    return
  fi
  rm -r -- "$TEST_ROOT"
}
trap cleanup EXIT

TEST_NUMBER=0
CURRENT_TEST=""

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

  [[ "$actual" == "$expected" ]] ||
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

create_repository() {
  local path="$1"
  local name="${path##*/}"

  mkdir -p -- "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.name "Task Workspace Test"
  git -C "$path" config user.email "task-workspace@example.invalid"
  git -C "$path" commit -q --allow-empty -m initial
  git -C "$path" remote add origin "https://example.invalid/$name.git"
}

run_task_workspace() {
  HOME="$TEST_HOME" zsh -f -c '
    source "$1"
    shift
    task-workspace "$@"
  ' task-workspace-test "$ALIASES_FILE" "$@"
}

run_successfully() {
  local log_file="$1"
  shift

  if ! run_task_workspace "$@" >"$log_file" 2>&1; then
    dump_log "$log_file"
    fail "task-workspace failed"
  fi
}

count_worktrees() {
  local repository="$1"

  git -C "$repository" worktree list --porcelain |
    awk '$1 == "worktree" { count++ } END { print count + 0 }'
}

test_compatible_invocation_creates_real_internal_worktree() {
  local case_root="$TEST_ROOT/compatible"
  local repository="$case_root/projects/repo-compatible"
  local workspace="$TEST_HOME/workspaces/feat/compatible"
  local canonical="$workspace/repo-compatible"
  local log_file="$case_root/task-workspace.log"
  local workspace_physical canonical_physical

  create_repository "$repository"
  git -C "$repository" branch feat/compatible main
  run_successfully "$log_file" \
    --from main feat/compatible "$repository"

  [[ -d "$canonical" ]] || fail "canonical repository directory was not created"
  [[ ! -L "$canonical" ]] || fail "canonical repository was represented by a symlink"
  [[ -f "$canonical/.git" && ! -d "$canonical/.git" ]] ||
    fail "canonical repository is not a linked Git worktree"

  workspace_physical=$(cd -- "$workspace" && pwd -P)
  canonical_physical=$(cd -- "$canonical" && pwd -P)
  [[ "$canonical_physical" == "$workspace_physical"/* ]] ||
    fail "canonical repository is not physically below the workspace root"
  assert_eq "$canonical_physical" \
    "$(git -C "$canonical" rev-parse --show-toplevel)" \
    "canonical path is not the exact Git root"
  assert_eq "feat/compatible" \
    "$(git -C "$canonical" symbolic-ref --quiet --short HEAD)" \
    "canonical branch did not match"
  assert_eq "$(git -C "$repository" remote get-url origin)" \
    "$(git -C "$canonical" remote get-url origin)" \
    "canonical origin did not match"

  jq -e '
    .workspace == "feat/compatible" and
    .goal == null and
    .sourceBranch == "main" and
    (.repositories | length) == 1 and
    .repositories[0].branch == "feat/compatible"
  ' "$workspace/.task-workspace.json" >/dev/null ||
    fail "backward-compatible invocation generated incorrect metadata"
}

test_goal_generates_manifest_and_agents_contract() {
  local case_root="$TEST_ROOT/goal"
  local repository_a="$case_root/projects/repo-a"
  local repository_b="$case_root/projects/repo-b"
  local workspace="$case_root/workspaces/feat-goal"
  local goal="Implement the task workspace contract without changing the worktree model."
  local log_file="$case_root/task-workspace.log"

  create_repository "$repository_a"
  create_repository "$repository_b"
  run_successfully "$log_file" \
    --from main --goal "$goal" --workspace "$workspace" feat/goal \
    "$repository_a" "$repository_b"

  jq -e --arg goal "$goal" --arg root "$(cd -- "$workspace" && pwd -P)" '
    .workspace == "feat/goal" and
    .goal == $goal and
    .sourceBranch == "main" and
    .root == $root and
    (.repositories | length) == 2 and
    ([.repositories[].branch] | all(. == "feat/goal")) and
    ([.repositories[].path] | all(startswith($root + "/"))) and
    ([.repositories[].origin] | all(startswith("https://example.invalid/")))
  ' "$workspace/.task-workspace.json" >/dev/null ||
    fail "goal invocation generated incorrect metadata"

  assert_contains "$workspace/AGENTS.md" "$goal" "AGENTS.md omitted the goal"
  assert_contains "$workspace/AGENTS.md" \
    "The repositories listed below are the canonical repositories for this task." \
    "AGENTS.md omitted the canonical repository contract"
  # Backticks and the glob are intentional literal contract text.
  # shellcheck disable=SC2016
  assert_contains "$workspace/AGENTS.md" \
    'Never create sibling or ad-hoc repositories such as `*-edit`' \
    "AGENTS.md omitted the replacement-repository prohibition"
  assert_contains "$workspace/AGENTS.md" \
    "STOP" "AGENTS.md omitted the blocker instruction"
  assert_contains "$workspace/AGENTS.md" \
    "path: $(cd -- "$workspace/repo-a" && pwd -P)" \
    "AGENTS.md omitted repo-a's canonical path"
  assert_contains "$workspace/AGENTS.md" \
    "path: $(cd -- "$workspace/repo-b" && pwd -P)" \
    "AGENTS.md omitted repo-b's canonical path"
}

test_rerun_reuses_worktree_and_updates_goal() {
  local case_root="$TEST_ROOT/rerun"
  local repository="$case_root/projects/repo-rerun"
  local workspace="$case_root/workspaces/feat-rerun"
  local canonical="$workspace/repo-rerun"
  local first_log="$case_root/first.log"
  local second_log="$case_root/second.log"
  local before_count before_git_dir

  create_repository "$repository"
  run_successfully "$first_log" \
    --from main --goal "First goal" --workspace "$workspace" feat/rerun "$repository"
  before_count=$(count_worktrees "$repository")
  before_git_dir=$(git -C "$canonical" rev-parse --git-dir)

  run_successfully "$second_log" \
    --from main --goal "Updated goal" --workspace "$workspace" feat/rerun "$repository"

  assert_eq "$before_count" "$(count_worktrees "$repository")" \
    "rerun created a duplicate worktree"
  assert_eq "$before_git_dir" "$(git -C "$canonical" rev-parse --git-dir)" \
    "rerun replaced the canonical worktree"
  jq -e '.goal == "Updated goal"' "$workspace/.task-workspace.json" >/dev/null ||
    fail "rerun did not update the goal"
  assert_contains "$second_log" "REUSE_WORKTREE" \
    "rerun did not report canonical worktree reuse"
}

test_unrelated_target_path_fails_without_replacement() {
  local case_root="$TEST_ROOT/unrelated-target"
  local repository="$case_root/projects/repo-unrelated"
  local workspace="$case_root/workspaces/feat-unrelated"
  local target="$workspace/repo-unrelated"
  local log_file="$case_root/task-workspace.log"

  create_repository "$repository"
  mkdir -p -- "$target"

  if run_task_workspace \
    --from main --workspace "$workspace" feat/unrelated "$repository" \
    >"$log_file" 2>&1; then
    fail "unrelated target path was accepted"
  fi
  assert_contains "$log_file" "target path is not a Git worktree:" \
    "unrelated target failure was not clear"
  assert_absent "$workspace/.task-workspace.json" \
    "manifest was generated for an invalid canonical path"
  assert_absent "$workspace/repo-unrelated-edit" "replacement -edit repository was created"
  assert_absent "$workspace/repo-unrelated-tmp" "replacement -tmp repository was created"
  assert_absent "$workspace/repo-unrelated-copy" "replacement -copy repository was created"
  assert_absent "$workspace/repo-unrelated-new" "replacement -new repository was created"
}

test_external_branch_checkout_fails_without_symlink_or_clone() {
  local case_root="$TEST_ROOT/external-branch"
  local repository="$case_root/projects/repo-branch"
  local existing_worktree="$case_root/existing/repo-branch"
  local workspace="$case_root/workspaces/feat-branch"
  local requested_path="$workspace/repo-branch"
  local log_file="$case_root/task-workspace.log"
  local existing_physical requested_physical

  create_repository "$repository"
  mkdir -p -- "${existing_worktree%/*}" "${workspace%/*}"
  git -C "$repository" worktree add -q -b feat/conflicting "$existing_worktree" main
  existing_physical=$(cd -- "$existing_worktree" && pwd -P)
  requested_physical="$(cd -- "${workspace%/*}" && pwd -P)/${workspace##*/}/repo-branch"

  if run_task_workspace \
    --from main --target-branch feat/conflicting --workspace "$workspace" \
    feat/branch "$repository" >"$log_file" 2>&1; then
    fail "branch checked out in an external worktree was accepted"
  fi

  assert_contains "$log_file" "repository: repo-branch" \
    "branch conflict omitted the repository"
  assert_contains "$log_file" "requested branch: feat/conflicting" \
    "branch conflict omitted the requested branch"
  assert_contains "$log_file" "existing worktree: $existing_physical" \
    "branch conflict omitted the existing worktree"
  assert_contains "$log_file" "requested workspace path: $requested_physical" \
    "branch conflict omitted the requested workspace path"
  assert_absent "$requested_path" \
    "conflicting canonical child was created or represented by a symlink"
  assert_absent "$workspace/.task-workspace.json" \
    "manifest was generated despite the branch conflict"
  assert_absent "$workspace/repo-branch-edit" "replacement -edit repository was created"
  assert_absent "$workspace/repo-branch-tmp" "replacement -tmp repository was created"
  assert_absent "$workspace/repo-branch-copy" "replacement -copy repository was created"
  assert_absent "$workspace/repo-branch-new" "replacement -new repository was created"
}

run_test() {
  local description="$1"
  local test_function="$2"

  TEST_NUMBER=$((TEST_NUMBER + 1))
  CURRENT_TEST="$description"
  "$test_function"
  printf 'ok %s - %s\n' "$TEST_NUMBER" "$description"
}

run_test \
  "compatible invocation creates a real internal worktree, never a symlink" \
  test_compatible_invocation_creates_real_internal_worktree
run_test \
  "goal generates canonical manifest and AGENTS contract" \
  test_goal_generates_manifest_and_agents_contract
run_test \
  "rerun reuses the canonical worktree and updates metadata" \
  test_rerun_reuses_worktree_and_updates_goal
run_test \
  "unrelated target path fails without a replacement repository" \
  test_unrelated_target_path_fails_without_replacement
run_test \
  "external branch checkout fails without a symlink or replacement clone" \
  test_external_branch_checkout_fails_without_symlink_or_clone

printf '1..%s\n' "$TEST_NUMBER"
