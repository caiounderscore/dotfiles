# Task workspaces: canonical multi-repository Git worktrees, a status report, archiving,
# and tuicr review. Sourced from .zshrc after .aliases.

# Create a task workspace with one Git worktree per repository. The source
# branch is explicit and all validation completes before any worktree is made.
task-workspace() {
  local usage="Usage: task-workspace --from <source-branch> [--goal <task-objective>] [--workspace <path>] [--target-branch <branch>] <workspace-name> <repository> [repository ...]"
  local source_branch="" goal="" workspace_override="" target_branch="" workspace_name=""
  local workspace_input workspace_path source repo_root repo_name target_path
  local source_ref source_commit common_dir target_commit target_action
  local remote_ref remote_name_branch checked_out merge_base origin
  local target_repo_root target_common_dir target_origin existing_branch target_physical
  local requested_branch parent contract_path repositories_json manifest_tmp agents_tmp
  local manifest_path agents_path invariant_checked_out
  local -a repositories repo_names common_dirs origins source_refs source_commits
  local -a target_paths target_actions target_commits target_merge_bases problems created
  local -a invariant_problems
  local -i index=1 inner=1

  while (( $# )); do
    case "$1" in
      --from)
        (( $# >= 2 )) || { echo "$usage" >&2; return 1; }
        source_branch="$2"
        shift 2
        ;;
      --goal)
        (( $# >= 2 )) || { echo "$usage" >&2; return 1; }
        goal="$2"
        [[ -n "$goal" ]] || problems+=("--goal must not be empty")
        shift 2
        ;;
      --workspace)
        (( $# >= 2 )) || { echo "$usage" >&2; return 1; }
        workspace_override="$2"
        shift 2
        ;;
      --target-branch)
        (( $# >= 2 )) || { echo "$usage" >&2; return 1; }
        target_branch="$2"
        shift 2
        ;;
      --)
        shift
        while (( $# )); do
          if [[ -z "$workspace_name" ]]; then
            workspace_name="$1"
          else
            repositories+=("$1")
          fi
          shift
        done
        ;;
      -*)
        problems+=("unknown option: $1")
        shift
        ;;
      *)
        if [[ -z "$workspace_name" ]]; then
          workspace_name="$1"
        else
          repositories+=("$1")
        fi
        shift
        ;;
    esac
  done

  [[ -n "$source_branch" ]] || problems+=("--from <source-branch> is required")
  [[ -n "$workspace_name" ]] || problems+=("workspace name is required")
  (( ${#repositories[@]} > 0 )) || problems+=("at least one repository is required")
  command -v git >/dev/null 2>&1 || problems+=("git is required")
  command -v jq >/dev/null 2>&1 || problems+=("jq is required")

  if [[ -n "$workspace_name" ]]; then
    if [[ "$workspace_name" == /* || "$workspace_name" == */ ||
          "$workspace_name" == *//* || "$workspace_name" == "." ||
          "$workspace_name" == ".." || "$workspace_name" == ../* ||
          "$workspace_name" == */../* || "$workspace_name" == */.. ||
          "$workspace_name" == */./* || "$workspace_name" == */. ]]; then
      problems+=("invalid workspace name path: $workspace_name")
    fi
  fi

  if [[ -n "$source_branch" ]]; then
    if ! git check-ref-format --branch "$source_branch" >/dev/null 2>&1 ||
       [[ "$source_branch" == refs/* ]]; then
      problems+=("invalid source branch name: $source_branch")
    fi
  fi

  if [[ -z "$target_branch" && -n "$workspace_name" ]]; then
    target_branch="$workspace_name"
  fi
  if [[ -n "$target_branch" ]] &&
     ! git check-ref-format --branch "$target_branch" >/dev/null 2>&1; then
    problems+=("invalid target branch name: $target_branch")
  fi

  if (( ${#problems[@]} == 0 )); then
    if [[ -n "$workspace_override" ]]; then
      workspace_input="$workspace_override"
    else
      workspace_input="${HOME}/workspaces/${workspace_name}"
    fi
    workspace_path="${workspace_input:A}"

    if [[ -L "$workspace_input" ]]; then
      problems+=("workspace root is a symlink: $workspace_input")
    elif [[ -e "$workspace_path" && ! -d "$workspace_path" ]]; then
      problems+=("workspace path is not a directory: $workspace_path")
    elif [[ -d "$workspace_path" && ! -w "$workspace_path" ]]; then
      problems+=("workspace directory is not writable: $workspace_path")
    else
      parent="$workspace_path"
      while [[ ! -e "$parent" && "$parent" != "/" ]]; do
        parent="${parent:h}"
      done
      [[ -d "$parent" && -w "$parent" ]] ||
        problems+=("workspace parent is not writable: $parent")
    fi

    manifest_path="$workspace_path/.task-workspace.json"
    agents_path="$workspace_path/AGENTS.md"
    for contract_path in "$manifest_path" "$agents_path"; do
      if [[ -L "$contract_path" ]]; then
        problems+=("workspace contract path is a symlink: $contract_path")
      elif [[ -e "$contract_path" && ! -f "$contract_path" ]]; then
        problems+=("workspace contract path is not a regular file: $contract_path")
      fi
    done
  fi

  for source in "${repositories[@]}"; do
    source="${source:A}"
    if [[ ! -d "$source" ]]; then
      problems+=("repository directory not found: $source")
      continue
    fi

    repo_root=$(git -C "$source" rev-parse --show-toplevel 2>/dev/null) || {
      problems+=("not a Git repository or worktree: $source")
      continue
    }
    repo_root="${repo_root:A}"
    if [[ "$repo_root" != "$source" ]]; then
      problems+=("repository path is not an exact root: $source")
      continue
    fi

    common_dir=$(git -C "$source" rev-parse --git-common-dir 2>/dev/null) || {
      problems+=("cannot resolve Git common directory: $source")
      continue
    }
    [[ "$common_dir" == /* ]] || common_dir="$source/$common_dir"
    common_dir="${common_dir:A}"
    repo_name="${repo_root:t}"

    if [[ "$repo_name" == "AGENTS.md" || "$repo_name" == ".task-workspace.json" ]]; then
      problems+=("repository name conflicts with a workspace contract file: $repo_name")
    fi

    for (( inner = 1; inner <= ${#common_dirs[@]}; inner++ )); do
      [[ "${common_dirs[inner]}" == "$common_dir" ]] &&
        problems+=("duplicate underlying repository: $source")
    done
    for (( inner = 1; inner <= ${#repo_names[@]}; inner++ )); do
      [[ "${repo_names[inner]}" == "$repo_name" ]] &&
        problems+=("duplicate repository target name: $repo_name")
    done

    if [[ "$source_branch" == origin/* ]]; then
      source_ref="refs/remotes/$source_branch"
    else
      source_ref="refs/heads/$source_branch"
    fi
    if ! git -C "$source" show-ref --verify --quiet "$source_ref"; then
      problems+=("source branch not found in $source: $source_branch")
      source_commit=""
    else
      source_commit=$(git -C "$source" rev-parse --verify "$source_ref^{commit}" 2>/dev/null) || {
        problems+=("source branch does not resolve to a commit in $source: $source_branch")
        source_commit=""
      }
    fi

    origin=$(git -C "$source" remote get-url origin 2>/dev/null) || {
      problems+=("origin remote not found in repository: $source")
      origin=""
    }

    repo_names+=("$repo_name")
    common_dirs+=("$common_dir")
    origins+=("$origin")
    source_refs+=("$source_ref")
    source_commits+=("$source_commit")
    target_paths+=("$workspace_path/$repo_name")
    target_commits+=("")
    target_actions+=("")
    target_merge_bases+=("")
  done

  if (( ${#problems[@]} == 0 )); then
    if [[ "$source_branch" != origin/* && "$source_branch" == "$target_branch" ]]; then
      problems+=("source and target branches are the same local branch: $target_branch")
    fi

    for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
      source="${repositories[index]:A}"
      target_path="${target_paths[index]}"
      target_commit=""
      merge_base=""
      checked_out=""

      if git -C "$source" show-ref --verify --quiet "refs/heads/$target_branch"; then
        target_action="REUSE_BRANCH"
        target_commit=$(git -C "$source" rev-parse --verify "refs/heads/$target_branch^{commit}" 2>/dev/null) || {
          problems+=("target branch does not resolve to a commit in $source: $target_branch")
          target_commit=""
        }
        checked_out=$(git -C "$source" worktree list --porcelain 2>/dev/null | awk \
          -v wanted="refs/heads/$target_branch" \
          '$1 == "worktree" { path = substr($0, 10) } $1 == "branch" && $2 == wanted { print path; exit }')
        [[ -z "$checked_out" ]] || checked_out="${checked_out:A}"
        if [[ -n "$target_commit" ]]; then
          merge_base=$(git -C "$source" merge-base "${source_commits[index]}" "$target_commit" 2>/dev/null) || {
            problems+=("no merge base between $source_branch and $target_branch in $source")
            merge_base=""
          }
        fi
      else
        remote_name_branch=""
        while IFS= read -r remote_ref; do
          remote_name_branch="${remote_ref#refs/remotes/}"
          [[ "$remote_name_branch" == */"$target_branch" ]] && break
          remote_name_branch=""
        done < <(git -C "$source" for-each-ref --format='%(refname)' refs/remotes)
        if [[ -n "$remote_name_branch" ]]; then
          problems+=("target branch exists only as a remote-tracking branch in $source: $target_branch")
          target_action="CREATE_BRANCH"
        else
          target_action="CREATE_BRANCH"
        fi
      fi

      if [[ -L "$target_path" ]]; then
        problems+=("canonical repository path is a symlink: $target_path")
      elif [[ -e "$target_path" ]]; then
        if [[ ! -d "$target_path" ]]; then
          problems+=("canonical repository path is not a directory: $target_path")
        else
          [[ -w "$target_path" ]] ||
            problems+=("canonical repository path is not writable: $target_path")
          target_physical="${target_path:A}"
          if [[ "$target_physical" != "$workspace_path"/* ]]; then
            problems+=("canonical repository is outside the workspace root: $target_path")
          fi

          target_repo_root=$(git -C "$target_path" rev-parse --show-toplevel 2>/dev/null) || {
            problems+=("target path is not a Git worktree: $target_path")
            target_repo_root=""
          }
          if [[ -n "$target_repo_root" ]]; then
            target_repo_root="${target_repo_root:A}"
            [[ "$target_repo_root" == "$target_physical" ]] ||
              problems+=("target path is not an exact Git worktree root: $target_path")
          fi

          target_common_dir=$(git -C "$target_path" rev-parse --git-common-dir 2>/dev/null) || {
            problems+=("cannot resolve target Git common directory: $target_path")
            target_common_dir=""
          }
          if [[ -n "$target_common_dir" ]]; then
            [[ "$target_common_dir" == /* ]] || target_common_dir="$target_path/$target_common_dir"
            target_common_dir="${target_common_dir:A}"
            [[ "$target_common_dir" == "${common_dirs[index]}" ]] ||
              problems+=("target path belongs to a different repository: $target_path")
          fi

          target_origin=$(git -C "$target_path" remote get-url origin 2>/dev/null) || {
            problems+=("origin remote not found in target worktree: $target_path")
            target_origin=""
          }
          if [[ -n "$target_origin" && "$target_origin" != "${origins[index]}" ]]; then
            problems+=("target origin does not match requested repository: $target_path")
          fi

          existing_branch=$(git -C "$target_path" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
            existing_branch=""
          if [[ "$existing_branch" != "$target_branch" ]]; then
            problems+=("target branch mismatch in $target_path: expected $target_branch, found ${existing_branch:-detached HEAD}")
          fi

          if [[ -z "$checked_out" ]]; then
            problems+=("target path is not the registered worktree for branch $target_branch: $target_path")
          elif [[ "$checked_out" != "$target_physical" ]]; then
            problems+=("worktree conflict:
      repository: $repo_name
      requested branch: $target_branch
      existing worktree: $checked_out
      requested workspace path: $target_path")
          elif [[ -n "$target_repo_root" && -n "$target_common_dir" &&
                  "$target_repo_root" == "$target_physical" &&
                  "$target_common_dir" == "${common_dirs[index]}" &&
                  "$target_origin" == "${origins[index]}" &&
                  "$existing_branch" == "$target_branch" ]]; then
            target_action="REUSE_WORKTREE"
          fi
        fi
      elif [[ -n "$checked_out" ]]; then
        problems+=("worktree conflict:
      repository: $repo_name
      requested branch: $target_branch
      existing worktree: $checked_out
      requested workspace path: $target_path")
      fi

      target_actions[index]="$target_action"
      target_commits[index]="$target_commit"
      target_merge_bases[index]="$merge_base"
    done
  fi

  if (( ${#problems[@]} > 0 )); then
    echo "Task workspace preflight failed:" >&2
    for requested_branch in "${problems[@]}"; do
      echo "  - $requested_branch" >&2
    done
    return 1
  fi

  printf '%s\n' 'Task workspace plan'
  printf '  name:          %s\n' "$workspace_name"
  printf '  path:          %s\n' "$workspace_path"
  printf '  source branch: %s\n' "$source_branch"
  printf '  target branch: %s\n\n' "$target_branch"
  for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
    printf '  %s\n' "${repo_names[index]}"
    printf '    source: %s @ %s\n' "${source_refs[index]}" "${source_commits[index]:0:7}"
    printf '    target: %s' "${target_actions[index]}"
    [[ "${target_actions[index]}" == REUSE_BRANCH ||
       "${target_actions[index]}" == REUSE_WORKTREE ]] &&
      printf ' @ %s (merge-base %s)' "${target_commits[index]:0:7}" "${target_merge_bases[index]:0:7}"
    printf '\n    path:   %s\n' "${target_paths[index]}"
  done
  printf '\n'

  mkdir -p -- "$workspace_path" || {
    echo "task-workspace: failed to create workspace: $workspace_path" >&2
    return 1
  }

  for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
    source="${repositories[index]:A}"
    if [[ "${target_actions[index]}" == REUSE_WORKTREE ]]; then
      continue
    elif [[ "${target_actions[index]}" == CREATE_BRANCH ]]; then
      git -C "$source" worktree add -b "$target_branch" \
        "${target_paths[index]}" "${source_commits[index]}" || {
        echo "Task workspace creation failed after partial progress." >&2
        for requested_branch in "${created[@]}"; do
          echo "  created: $requested_branch" >&2
        done
        echo "  failed:  ${target_paths[index]}" >&2
        echo "Caller directory was not changed; no automatic cleanup was performed." >&2
        return 1
      }
    else
      git -C "$source" worktree add \
        "${target_paths[index]}" "$target_branch" || {
        echo "Task workspace creation failed after partial progress." >&2
        for requested_branch in "${created[@]}"; do
          echo "  created: $requested_branch" >&2
        done
        echo "  failed:  ${target_paths[index]}" >&2
        echo "Caller directory was not changed; no automatic cleanup was performed." >&2
        return 1
      }
    fi
    created+=("${target_paths[index]}")
  done

  # Do not publish a workspace contract until every canonical path proves that
  # it is the requested, physically contained worktree.
  for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
    source="${repositories[index]:A}"
    target_path="${target_paths[index]}"

    if [[ -L "$target_path" || ! -d "$target_path" ]]; then
      invariant_problems+=("canonical path is not a real directory: $target_path")
      continue
    fi
    [[ -w "$target_path" ]] ||
      invariant_problems+=("canonical path is not writable: $target_path")

    target_physical="${target_path:A}"
    [[ "$target_physical" == "$workspace_path"/* ]] ||
      invariant_problems+=("canonical path is outside the workspace root: $target_path")

    target_repo_root=$(git -C "$target_path" rev-parse --show-toplevel 2>/dev/null) || {
      invariant_problems+=("canonical path is not a Git worktree: $target_path")
      target_repo_root=""
    }
    if [[ -n "$target_repo_root" ]]; then
      target_repo_root="${target_repo_root:A}"
      [[ "$target_repo_root" == "$target_physical" ]] ||
        invariant_problems+=("canonical path is not an exact Git worktree root: $target_path")
    fi

    target_common_dir=$(git -C "$target_path" rev-parse --git-common-dir 2>/dev/null) || {
      invariant_problems+=("cannot resolve canonical Git common directory: $target_path")
      target_common_dir=""
    }
    if [[ -n "$target_common_dir" ]]; then
      [[ "$target_common_dir" == /* ]] || target_common_dir="$target_path/$target_common_dir"
      target_common_dir="${target_common_dir:A}"
      [[ "$target_common_dir" == "${common_dirs[index]}" ]] ||
        invariant_problems+=("canonical path belongs to a different repository: $target_path")
    fi

    target_origin=$(git -C "$target_path" remote get-url origin 2>/dev/null) || {
      invariant_problems+=("origin remote not found in canonical worktree: $target_path")
      target_origin=""
    }
    [[ "$target_origin" == "${origins[index]}" ]] ||
      invariant_problems+=("canonical origin does not match requested repository: $target_path")

    existing_branch=$(git -C "$target_path" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
      existing_branch=""
    [[ "$existing_branch" == "$target_branch" ]] ||
      invariant_problems+=("canonical branch mismatch in $target_path: expected $target_branch, found ${existing_branch:-detached HEAD}")

    invariant_checked_out=$(git -C "$source" worktree list --porcelain 2>/dev/null | awk \
      -v wanted="refs/heads/$target_branch" \
      '$1 == "worktree" { path = substr($0, 10) } $1 == "branch" && $2 == wanted { print path; exit }')
    [[ -z "$invariant_checked_out" ]] || invariant_checked_out="${invariant_checked_out:A}"
    [[ "$invariant_checked_out" == "$target_physical" ]] ||
      invariant_problems+=("canonical path is not the registered worktree for branch $target_branch: $target_path")
  done

  if (( ${#invariant_problems[@]} > 0 )); then
    echo "Task workspace invariant check failed:" >&2
    for requested_branch in "${invariant_problems[@]}"; do
      echo "  - $requested_branch" >&2
    done
    echo "No workspace contract was generated; no automatic cleanup was performed." >&2
    return 1
  fi

  repositories_json='[]'
  for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
    repositories_json=$(jq -c \
      --arg name "${repo_names[index]}" \
      --arg path "${target_paths[index]}" \
      --arg branch "$target_branch" \
      --arg origin "${origins[index]}" \
      '. + [{name: $name, path: $path, branch: $branch, origin: $origin}]' \
      <<<"$repositories_json") || {
      echo "task-workspace: failed to prepare repository metadata" >&2
      return 1
    }
  done

  manifest_tmp=$(mktemp "$workspace_path/.task-workspace.json.tmp.XXXXXX") || {
    echo "task-workspace: failed to create temporary manifest" >&2
    return 1
  }
  agents_tmp=$(mktemp "$workspace_path/AGENTS.md.tmp.XXXXXX") || {
    command rm -f -- "$manifest_tmp"
    echo "task-workspace: failed to create temporary workspace instructions" >&2
    return 1
  }

  if ! jq -n \
    --arg workspace "$workspace_name" \
    --arg goal "$goal" \
    --arg source_branch "$source_branch" \
    --arg root "$workspace_path" \
    --argjson repositories "$repositories_json" \
    '{
      workspace: $workspace,
      goal: (if $goal == "" then null else $goal end),
      sourceBranch: $source_branch,
      root: $root,
      repositories: $repositories
    }' >"$manifest_tmp"; then
    command rm -f -- "$manifest_tmp" "$agents_tmp"
    echo "task-workspace: failed to generate workspace manifest" >&2
    return 1
  fi

  if ! {
    printf '# Task Workspace\n\n'
    printf 'Goal:\n\n%s\n\n' "${goal:-Not specified.}"
    printf 'Workspace root:\n\n%s\n\n' "$workspace_path"
    cat <<'EOF'
## Canonical repository contract

- The repositories listed below are the canonical repositories for this task.
- Work only in these existing worktrees.
- Never create replacement clones for a repository already present in this workspace.
- Never create sibling or ad-hoc repositories such as `*-edit`, `*-tmp`, `*-copy`, `*-new`, or temporary replacement clones.
- Never clone around a dirty worktree, an active merge or rebase, a detached HEAD, a branch already checked out elsewhere, filesystem permissions, or tooling limitations.
- If a canonical worktree cannot be safely modified, **STOP** and report the exact blocker.
- Never silently switch the implementation to `main` or another clone.
- Before editing a repository, inspect `git status`, the current branch, and `HEAD`.
- Repository-local `AGENTS.md` and `CLAUDE.md` instructions remain applicable in addition to this workspace-level contract.

## Canonical repositories

EOF
    for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
      printf -- '- %s\n  path: %s\n  branch: %s\n\n' \
        "${repo_names[index]}" "${target_paths[index]}" "$target_branch"
    done
  } >"$agents_tmp"; then
    command rm -f -- "$manifest_tmp" "$agents_tmp"
    echo "task-workspace: failed to generate workspace instructions" >&2
    return 1
  fi

  chmod 644 "$manifest_tmp" "$agents_tmp" || {
    command rm -f -- "$manifest_tmp" "$agents_tmp"
    echo "task-workspace: failed to set workspace contract permissions" >&2
    return 1
  }
  mv -- "$manifest_tmp" "$manifest_path" || {
    command rm -f -- "$manifest_tmp" "$agents_tmp"
    echo "task-workspace: failed to install workspace manifest" >&2
    return 1
  }
  mv -- "$agents_tmp" "$agents_path" || {
    command rm -f -- "$agents_tmp"
    echo "task-workspace: failed to install workspace instructions" >&2
    return 1
  }

  # Preserve the established behavior: the caller lands at the workspace root,
  # never inside one of the child repositories.
  cd -- "$workspace_path" || return 1

  printf 'Workspace ready:\n  %s\n\n' "$workspace_path"
  printf 'Goal:\n  %s\n\n' "${goal:-Not specified.}"
  printf 'Canonical repositories:\n'
  for (( index = 1; index <= ${#repo_names[@]}; index++ )); do
    printf '  %s → %s\n' "${repo_names[index]}" "$target_branch"
  done
  printf '\nWorkspace contract:\n  %s\n\n' "$agents_path"
  printf '%s\n' \
    'AI agents must use these worktrees.' \
    'If a canonical worktree is blocked, report the blocker instead of creating another clone.'

  # Optional: show these worktrees in Orca when its CLI is on PATH; nothing depends on it.
  if command -v orca >/dev/null 2>&1; then
    for (( index = 1; index <= ${#target_paths[@]}; index++ )); do
      common_dir=$(git -C "${target_paths[index]}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
        continue
      orca repo set --repo "path:${common_dir:h}" --external-worktree-visibility show >/dev/null 2>&1 || true
    done
  fi
}

# Report every task workspace with each repository's branch, last commit, and whether it is
# dirty or has commits no remote branch contains, so finished workspaces can be archived.
workspaces() {
  local root="${1:-$HOME/workspaces}" manifest repo_path last
  local -a repo_paths state

  for manifest in "$root"/**/.task-workspace.json(N); do
    [[ "$manifest" == */.archive/* ]] && continue
    printf '%s\n' "${${manifest:h}#$root/}"
    repo_paths=("${(@f)$(jq -r '.repositories[].path' "$manifest")}")
    for repo_path in "${repo_paths[@]}"; do
      if [[ ! -d "$repo_path" ]]; then
        printf '  %-28s missing\n' "${repo_path:t}"
        continue
      fi
      state=()
      [[ -n "$(git -C "$repo_path" status --porcelain)" ]] && state+=(dirty)
      [[ -n "$(git -C "$repo_path" branch -r --contains HEAD 2>/dev/null)" ]] || state+=(unpushed)
      last=$(git -C "$repo_path" log -1 --format=%cr)
      printf '  %-28s %-36s %-16s %s\n' "${repo_path:t}" \
        "$(git -C "$repo_path" branch --show-current)" "$last" "${state[*]:-clean}"
    done
  done
}

# Archive a finished task workspace. Refuses dirty or unpushed repositories, moves ignored
# files (such as .scratch trackers and .env files, which `git worktree remove` would delete)
# and the root files into the archive, then removes the worktrees. Branches stay intact.
task-workspace-archive() {
  local usage="Usage: task-workspace-archive <workspace-path|workspace-name>"
  local ws manifest archive repo_path common_dir rel
  local -a repo_paths problems

  (( $# == 1 )) || { echo "$usage" >&2; return 1; }
  if [[ -d "$1" ]]; then ws="$1"; else ws="${HOME}/workspaces/$1"; fi
  [[ -L "$ws" ]] && { echo "task-workspace-archive: workspace root is a symlink: $ws" >&2; return 1; }
  ws="${ws:A}"
  manifest="$ws/.task-workspace.json"
  if [[ ! -f "$manifest" || "$(jq -r '.root // empty' "$manifest")" != "$ws" ]]; then
    echo "task-workspace-archive: not a task workspace: $ws" >&2
    return 1
  fi

  repo_paths=("${(@f)$(jq -r '.repositories[].path' "$manifest")}")
  for repo_path in "${repo_paths[@]}"; do
    [[ -d "$repo_path" ]] || continue
    if [[ "${repo_path:A}" != "$ws"/* || ! -f "$repo_path/.git" ]]; then
      problems+=("${repo_path}: not a linked worktree inside the workspace")
      continue
    fi
    [[ -z "$(git -C "$repo_path" status --porcelain)" ]] || problems+=("${repo_path:t}: uncommitted changes")
    [[ -n "$(git -C "$repo_path" branch -r --contains HEAD 2>/dev/null)" ]] ||
      problems+=("${repo_path:t}: commits that no remote branch contains")
  done
  if (( ${#problems[@]} )); then
    printf 'task-workspace-archive: %s\n' "${problems[@]}" >&2
    return 1
  fi

  archive="${WORKSPACE_ARCHIVE_DIR:-$HOME/workspaces/.archive}/${ws:t}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p -- "$archive" || return 1
  for repo_path in "${repo_paths[@]}"; do
    [[ -d "$repo_path" ]] || continue
    # Sorted so a directory moves before its own entries, which are then already gone.
    git -C "$repo_path" ls-files -z --others --ignored --exclude-standard --directory | sort -z |
      while IFS= read -r -d '' rel; do
        rel="${rel%/}"
        [[ -e "$repo_path/$rel" || -L "$repo_path/$rel" ]] || continue
        mkdir -p -- "$archive/${repo_path:t}/${rel:h}" &&
          mv -- "$repo_path/$rel" "$archive/${repo_path:t}/$rel" || return 1
      done || { echo "task-workspace-archive: failed to keep ignored files of ${repo_path:t}" >&2; return 1; }
    common_dir=$(git -C "$repo_path" rev-parse --path-format=absolute --git-common-dir) || return 1
    git --git-dir="$common_dir" worktree remove "$repo_path" || return 1
  done
  mv -- "$ws"/*(DN) "$archive"/ && rmdir -- "$ws" || return 1
  printf 'Archived %s to %s\n' "$ws" "$archive"
}

# Repeatedly select immediate child repositories in the current task workspace
# and open them in tuicr. A supplied range is passed unchanged after validation.
review() {
  if (( $# > 1 )); then
    echo "Usage: review [git-revision-range]" >&2
    return 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "review: fzf is required" >&2
    return 1
  fi
  if ! command -v tuicr >/dev/null 2>&1; then
    echo "review: tuicr is required" >&2
    return 1
  fi

  local workspace="${PWD:A}"
  local revision_range="${1:-}"
  local base_revision head_revision base_commit head_commit selected_root
  local repo_dir repo_root repo_name branch changed change_summary label selected selected_repo selected_changed marker
  local tuicr_status
  local -i index
  local -a repo_dirs repo_changes labels

  if [[ -n "$revision_range" ]]; then
    if [[ "$revision_range" == *"..."* ]]; then
      base_revision="${revision_range%%...*}"
      head_revision="${revision_range#*...}"
    elif [[ "$revision_range" == *".."* ]]; then
      base_revision="${revision_range%%..*}"
      head_revision="${revision_range#*..}"
    else
      echo "review: range must use base..head or base...head" >&2
      return 1
    fi

    if [[ -z "$base_revision" || -z "$head_revision" ||
          "$base_revision" == -* || "$head_revision" == -* ||
          "$base_revision" == *".."* || "$head_revision" == *".."* ]]; then
      echo "review: range must contain exactly two non-empty revisions" >&2
      return 1
    fi
  fi

  while true; do
    repo_dirs=()
    repo_changes=()
    labels=()
    selected_repo=""
    selected_changed=""
    index=1

    while IFS= read -r -d '' repo_dir; do
      repo_root=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null) || continue
      [[ "$repo_root" == "${repo_dir:A}" ]] || continue

      repo_name="${repo_dir:t}"
      branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || \
        branch="detached@$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)"
      changed=$(git -C "$repo_dir" status --short --untracked-files=all 2>/dev/null | awk 'END { print NR + 0 }')
      if (( changed == 0 )); then
        change_summary="clean"
      else
        change_summary="$changed changes"
      fi

      repo_dirs+=("$repo_dir")
      repo_changes+=("$changed")
      marker=""
      [[ -L "$repo_dir" ]] && marker=" legacy-symlink"
      label=$(printf '%-24s %-12s %-24s%s' "$repo_name" "$change_summary" "$branch" "$marker")
      labels+=("$label")
    done < <(find "$workspace" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null)

    if (( ${#repo_dirs[@]} == 0 )); then
      echo "review: no immediate child Git repositories found in $workspace" >&2
      return 1
    fi

    selected=$(printf '%s\n' "${labels[@]}" | fzf \
      --height=40% --layout=reverse --border \
      --header=$'Select repository to review · Esc to exit\nRepository                Changes      Branch') || return 0
    [[ -n "$selected" ]] || return 0

    while (( index <= ${#labels[@]} )); do
      if [[ "${labels[index]}" == "$selected" ]]; then
        selected_repo="${repo_dirs[index]}"
        selected_changed="${repo_changes[index]}"
        break
      fi
      (( index++ ))
    done

    [[ -n "$selected_repo" ]] || {
      echo "review: selected repository could not be resolved" >&2
      continue
    }
    [[ -d "$selected_repo" ]] || {
      echo "review: selected repository no longer exists: $selected_repo" >&2
      continue
    }
    selected_root=$(git -C "$selected_repo" rev-parse --show-toplevel 2>/dev/null) || {
      echo "review: selected path is no longer a Git repository: $selected_repo" >&2
      continue
    }
    [[ "${selected_root:A}" == "${selected_repo:A}" ]] || {
      echo "review: selected path is no longer a repository root: $selected_repo" >&2
      continue
    }

    if [[ -n "$revision_range" ]]; then
      base_commit=$(git -C "$selected_repo" rev-parse --verify "$base_revision^{commit}" 2>/dev/null) || {
        echo "review: ${selected_repo:t}: base revision is not a commit: $base_revision" >&2
        continue
      }
      head_commit=$(git -C "$selected_repo" rev-parse --verify "$head_revision^{commit}" 2>/dev/null) || {
        echo "review: ${selected_repo:t}: head revision is not a commit: $head_revision" >&2
        continue
      }
      if [[ "$base_commit" == "$head_commit" ]]; then
        echo "review: ${selected_repo:t}: base and head resolve to the same commit" >&2
        continue
      fi
    fi

    (
      cd -- "$selected_repo" || exit 1
      if [[ -n "$revision_range" ]]; then
        command tuicr -r "$revision_range"
      elif (( selected_changed > 0 )); then
        command tuicr -w
      else
        command tuicr
      fi
    )
    tuicr_status=$?
    if (( tuicr_status != 0 )); then
      echo "review: tuicr exited with status $tuicr_status for ${selected_repo:t}" >&2
    fi
  done
}
