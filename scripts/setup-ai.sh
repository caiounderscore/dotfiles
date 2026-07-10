#!/usr/bin/env bash
# Purpose: safely migrate shared AI instructions, portable skills, language state,
# and Claude/Codex adapters into their canonical GNU Stow layout.
# The default mode is read-only; filesystem changes require an explicit --apply.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly HOME_DIR="$(cd -- "${HOME:?HOME must be set}" && pwd -P)"
readonly LEGACY_SKILLS="$HOME_DIR/.agent/skills"
readonly CANONICAL_SKILLS="$HOME_DIR/.agents/skills"
readonly MANAGED_SKILLS="$REPO_DIR/ai/.agents/skills"
readonly LANGUAGE_STATE="$HOME_DIR/.agents/state/language"
readonly LANGUAGE_WARMUP_MARKER="$LANGUAGE_STATE/warmup-enabled"

apply=false
backup_dir=""
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  cat <<'EOF'
Usage: scripts/setup-ai.sh [--apply]

Safely inventory and migrate shared AI configuration into the canonical
~/.agents layout while preserving legacy roots, conflicts, and rollback data.

Without --apply, inventory skill roots, preview migrations, and simulate Stow.
With --apply, perform only the previewed non-destructive migrations and links.
EOF
}

while (($# > 0)); do
  case "$1" in
    --apply) apply=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'setup-ai: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '[ai-setup] %s\n' "$*"
}

warn() {
  printf '[ai-setup] WARNING: %s\n' "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'setup-ai: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

for command_name in awk cmp cp find jq join shasum sort stow; do
  require_command "$command_name"
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai.XXXXXX")
cleanup() {
  rm -r -- "$tmp_dir"
}
trap cleanup EXIT

skill_tree_hash() {
  local skill_dir="$1"

  (
    cd -- "$skill_dir"
    {
      find . -type f -exec shasum -a 256 {} + | awk '{ print "F\t" $0 }'
      find . -type l -exec sh -c '
        for entry do
          printf "L\t%s\t%s\n" "$entry" "$(readlink "$entry")"
        done
      ' sh {} +
      find . \( \
        -type d -o \
        \( -type f \( -perm -100 -o -perm -010 -o -perm -001 \) \) \
      \) -print
    } | LC_ALL=C sort
  ) | shasum -a 256 | awk '{print $1}'
}

build_skill_manifest() {
  local root="$1"
  local output="$2"
  local skill_dir
  local name

  : >"$output"
  [[ -d "$root" ]] || return 0

  while IFS= read -r skill_dir; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    name=$(basename -- "$skill_dir")
    printf '%s\t%s\n' "$name" "$(skill_tree_hash "$skill_dir")" >>"$output"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -print)
  LC_ALL=C sort -o "$output" "$output"
}

count_lines() {
  awk 'END { print NR + 0 }' "$1"
}

readonly SINGULAR_MANIFEST="$tmp_dir/singular.tsv"
readonly PLURAL_MANIFEST="$tmp_dir/plural.tsv"
readonly SHARED_MANIFEST="$tmp_dir/shared.tsv"
readonly SINGULAR_ONLY="$tmp_dir/singular-only.tsv"
readonly PLURAL_ONLY="$tmp_dir/plural-only.tsv"
readonly CONFLICTS="$tmp_dir/conflicts.tsv"

inventory_skills() {
  log "Hashing legacy skills under $LEGACY_SKILLS (this can take tens of seconds)"
  build_skill_manifest "$LEGACY_SKILLS" "$SINGULAR_MANIFEST"
  log "Hashing canonical skills under $CANONICAL_SKILLS (this can take tens of seconds)"
  build_skill_manifest "$CANONICAL_SKILLS" "$PLURAL_MANIFEST"

  log "Comparing skill manifests"
  LC_ALL=C join -t $'\t' "$SINGULAR_MANIFEST" "$PLURAL_MANIFEST" >"$SHARED_MANIFEST"
  LC_ALL=C join -t $'\t' -v 1 "$SINGULAR_MANIFEST" "$PLURAL_MANIFEST" >"$SINGULAR_ONLY"
  LC_ALL=C join -t $'\t' -v 2 "$SINGULAR_MANIFEST" "$PLURAL_MANIFEST" >"$PLURAL_ONLY"
  awk -F '\t' '$2 != $3' "$SHARED_MANIFEST" >"$CONFLICTS"

  local identical
  identical=$(awk -F '\t' '$2 == $3 { count++ } END { print count + 0 }' "$SHARED_MANIFEST")

  log "Skill inventory (top-level directories containing SKILL.md):"
  printf '  singular: %s\n' "$(count_lines "$SINGULAR_MANIFEST")"
  printf '  plural: %s\n' "$(count_lines "$PLURAL_MANIFEST")"
  printf '  shared identical: %s\n' "$identical"
  printf '  singular-only: %s\n' "$(count_lines "$SINGULAR_ONLY")"
  printf '  plural-only: %s\n' "$(count_lines "$PLURAL_ONLY")"
  printf '  same-name conflicts: %s\n' "$(count_lines "$CONFLICTS")"

  if [[ -s "$CONFLICTS" ]]; then
    log "Conflicts preserved in both roots:"
    while IFS=$'\t' read -r name singular_hash plural_hash; do
      printf '  %s  singular=%s  plural=%s\n' "$name" "$singular_hash" "$plural_hash"
    done <"$CONFLICTS"
    warn "After relinking, Claude will use the canonical plural-root version of each conflicting skill"
    warn "Legacy conflicting versions remain under $LEGACY_SKILLS for review or rollback"
  fi
}

preview_stow() {
  log "GNU Stow simulation for ai, claude, and codex:"
  stow --simulate --verbose=2 --no-folding \
    --dir="$REPO_DIR" --target="$HOME_DIR" ai claude codex
}

copy_singular_only_skills() {
  local name
  local hash
  local source
  local source_to_copy
  local target

  [[ -s "$SINGULAR_ONLY" ]] || return 0
  log "Singular-only skill plan:"

  while IFS=$'\t' read -r name hash; do
    source="$LEGACY_SKILLS/$name"
    target="$CANONICAL_SKILLS/$name"

    if [[ -f "$MANAGED_SKILLS/$name/SKILL.md" ]]; then
      printf '  %s: provided by the ai Stow package; legacy source retained\n' "$name"
      continue
    fi

    if [[ -e "$target" || -L "$target" ]]; then
      warn "$name appeared at the canonical root after inventory; leaving both untouched"
      continue
    fi

    if [[ "$apply" == true ]]; then
      mkdir -p -- "$CANONICAL_SKILLS"
      source_to_copy="$source"
      if [[ -L "$source" ]]; then
        source_to_copy=$(cd -- "$source" && pwd -P)
      fi
      cp -pR -- "$source_to_copy" "$target"
      printf '  %s: copied safely (hash %s)\n' "$name" "$hash"
    else
      if [[ -L "$source" ]]; then
        printf '  %s: would copy the resolved skill directory without overwriting (hash %s)\n' "$name" "$hash"
      else
        printf '  %s: would copy without overwriting (hash %s)\n' "$name" "$hash"
      fi
    fi
  done <"$SINGULAR_ONLY"
}

ensure_backup_dir() {
  local candidate

  if [[ -z "$backup_dir" ]]; then
    candidate="$HOME_DIR/.agents/state/backups/ai-migration-$timestamp"
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      backup_dir=$(mktemp -d "$candidate.XXXXXX")
    else
      backup_dir="$candidate"
      mkdir -p -- "$backup_dir"
    fi
  fi
}

backup_regular_file() {
  local source="$1"
  local label="$2"
  local destination

  ensure_backup_dir
  destination="$backup_dir/language/$label"
  mkdir -p -- "$(dirname -- "$destination")"
  if [[ ! -e "$destination" ]]; then
    cp -p -- "$source" "$destination"
    log "Backed up $source -> $destination"
  fi
}

preserve_log_conflict() {
  local source="$1"
  local digest
  local base
  local stem
  local destination

  digest=$(shasum -a 256 "$source" | awk '{print $1}')
  base=$(basename -- "$source")
  stem="${base%.*}"
  destination="$LANGUAGE_STATE/migration-conflicts/$stem.${digest:0:12}.md"

  if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then
    log "Conflict candidate already preserved: $destination"
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    warn "Conflict destination already exists with different content: $destination"
    return 0
  fi

  if [[ "$apply" == true ]]; then
    backup_regular_file "$source" "legacy/$(basename -- "$source")"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -p -- "$source" "$destination"
    log "Preserved divergent log: $destination"
  else
    log "Would back up and preserve divergent log as $destination"
  fi
}

migrate_log_group() {
  local target="$1"
  shift
  local -a sources=()
  local source
  local first
  local all_same=true

  for source in "$@"; do
    [[ -f "$source" && ! -L "$source" ]] && sources+=("$source")
  done
  ((${#sources[@]} > 0)) || return 0

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ ! -f "$target" || -L "$target" ]]; then
      warn "Neutral log path is not a regular file; leaving it untouched: $target"
      return 0
    fi
    for source in "${sources[@]}"; do
      if cmp -s "$source" "$target"; then
        log "Language log already migrated: $target"
      else
        preserve_log_conflict "$source"
      fi
    done
    return 0
  fi

  first="${sources[0]}"
  for source in "${sources[@]:1}"; do
    if ! cmp -s "$first" "$source"; then
      all_same=false
      break
    fi
  done

  if [[ "$all_same" == false ]]; then
    warn "Divergent sources found for $target; no canonical file will be chosen"
    for source in "${sources[@]}"; do
      preserve_log_conflict "$source"
    done
    return 0
  fi

  if [[ "$apply" == true ]]; then
    backup_regular_file "$first" "legacy/$(basename -- "$first")"
    mkdir -p -- "$(dirname -- "$target")"
    cp -p -- "$first" "$target"
    log "Migrated language log without altering its source: $target"
  else
    log "Would back up $first and copy it to $target"
  fi
}

migrate_auxiliary_language_state() {
  local source="$1"
  local target="$LANGUAGE_STATE/legacy/$(basename -- "$source")"

  [[ -f "$source" && ! -L "$source" ]] || return 0
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    warn "Auxiliary language state differs and was left at both paths: $source"
    return 0
  fi

  if [[ "$apply" == true ]]; then
    backup_regular_file "$source" "legacy/$(basename -- "$source")"
    mkdir -p -- "$(dirname -- "$target")"
    cp -p -- "$source" "$target"
    log "Copied auxiliary language state to $target"
  else
    log "Would back up and copy auxiliary language state to $target"
  fi
}

migrate_language_state() {
  migrate_log_group \
    "$LANGUAGE_STATE/english-mistakes-log.md" \
    "$HOME_DIR/.claude/english-mistakes-log.md"

  migrate_log_group \
    "$LANGUAGE_STATE/german-mistakes-log.md" \
    "$HOME_DIR/.claude/german-mistakes-log.md" \
    "$HOME_DIR/.claude/german-teacher-mistakes-log.md"

  migrate_auxiliary_language_state "$HOME_DIR/.claude/lang-warmup-english.txt"
  migrate_auxiliary_language_state "$HOME_DIR/.claude/lang-warmup-german.txt"
}

migrate_language_warmup_preference() {
  local legacy_settings="$HOME_DIR/.claude/settings.local.json"

  [[ -f "$legacy_settings" ]] || return 0
  warn "$legacy_settings is not a supported user settings layer; only project .claude/settings.local.json files are loaded"
  warn "Only the warm-up opt-in is migrated automatically; review any other keys manually"

  if [[ -e "$LANGUAGE_WARMUP_MARKER" || -L "$LANGUAGE_WARMUP_MARKER" ]]; then
    if [[ -f "$LANGUAGE_WARMUP_MARKER" ]]; then
      log "Language warm-up is already enabled by $LANGUAGE_WARMUP_MARKER"
      return 0
    fi
    warn "Language warm-up marker is not a regular file: $LANGUAGE_WARMUP_MARKER"
    return 1
  fi

  if ! jq empty "$legacy_settings" >/dev/null 2>&1; then
    warn "Cannot migrate the warm-up preference from invalid JSON: $legacy_settings"
    return 0
  fi

  if ! jq -e \
    '[.hooks.SessionStart[]?.hooks[]?.command? | strings | select(contains("lang-warmup.sh"))] | length > 0' \
    "$legacy_settings" >/dev/null; then
    return 0
  fi

  if [[ "$apply" == true ]]; then
    mkdir -p -- "$(dirname -- "$LANGUAGE_WARMUP_MARKER")"
    : >"$LANGUAGE_WARMUP_MARKER"
    log "Preserved the per-machine warm-up preference in $LANGUAGE_WARMUP_MARKER"
  else
    log "Would preserve the per-machine warm-up preference in $LANGUAGE_WARMUP_MARKER"
  fi
}

normalize_absolute_path() {
  local path="$1"
  local part
  local result="/"
  local -a input_parts=()
  local -a output_parts=()

  [[ "$path" == /* ]] || return 1
  IFS='/' read -r -a input_parts <<<"$path"
  for part in "${input_parts[@]}"; do
    case "$part" in
      ''|.) ;;
      ..)
        if ((${#output_parts[@]} > 0)); then
          unset "output_parts[$((${#output_parts[@]} - 1))]"
        fi
        ;;
      *) output_parts+=("$part") ;;
    esac
  done

  for part in "${output_parts[@]}"; do
    if [[ "$result" == / ]]; then
      result+="$part"
    else
      result+="/$part"
    fi
  done
  printf '%s\n' "$result"
}

canonical_path() {
  local path
  local parent

  path=$(normalize_absolute_path "$1")
  if [[ -d "$path" ]]; then
    (cd -- "$path" && pwd -P)
  elif [[ -e "$path" ]]; then
    parent=$(cd -- "$(dirname -- "$path")" && pwd -P)
    printf '%s/%s\n' "$parent" "$(basename -- "$path")"
  else
    printf '%s\n' "$path"
  fi
}

symlink_target_path() {
  local path="$1"
  local link_target

  [[ -L "$path" ]] || return 1
  link_target=$(readlink "$path")
  if [[ "$link_target" == /* ]]; then
    canonical_path "$link_target"
  else
    canonical_path "$(dirname -- "$path")/$link_target"
  fi
}

replace_symlink_with_backup() {
  local path="$1"
  local new_target="$2"
  local label="$3"
  local saved

  ensure_backup_dir
  saved="$backup_dir/$label"
  mkdir -p -- "$(dirname -- "$saved")"
  mv -- "$path" "$saved"
  if ! ln -s -- "$new_target" "$path"; then
    mv -- "$saved" "$path"
    return 1
  fi
  log "Backed up $path -> $saved"
  log "Linked $path -> $new_target"
}

point_claude_to_canonical_skills() {
  local path="$HOME_DIR/.claude/skills"
  local resolved=""

  if [[ -L "$path" ]]; then
    resolved=$(symlink_target_path "$path")
  fi

  if [[ "$resolved" == "$CANONICAL_SKILLS" ]]; then
    log "Claude skill root already resolves to $CANONICAL_SKILLS"
    return 0
  fi

  if [[ -e "$path" && ! -L "$path" ]]; then
    warn "$path is a real file or directory; refusing to replace it automatically"
    return 1
  fi

  if [[ "$apply" == true ]]; then
    mkdir -p -- "$HOME_DIR/.claude" "$CANONICAL_SKILLS"
    if [[ -L "$path" ]]; then
      replace_symlink_with_backup "$path" "$CANONICAL_SKILLS" "claude/skills"
    else
      ln -s -- "$CANONICAL_SKILLS" "$path"
      log "Linked $path -> $CANONICAL_SKILLS"
    fi
  elif [[ -L "$path" ]]; then
    log "Would back up $path and relink it to $CANONICAL_SKILLS"
  else
    log "Would link $path -> $CANONICAL_SKILLS"
  fi
}

retire_managed_symlink() {
  local path="$1"
  local managed="$2"
  local label="$3"
  local resolved
  local expected
  local saved

  [[ -L "$path" ]] || return 0
  resolved=$(symlink_target_path "$path")
  expected=$(canonical_path "$managed")
  [[ "$resolved" == "$expected" ]] || return 0

  if [[ "$apply" == true ]]; then
    ensure_backup_dir
    saved="$backup_dir/$label"
    if [[ -e "$saved" || -L "$saved" ]]; then
      warn "Refusing to overwrite an existing migration backup: $saved"
      return 1
    fi
    mkdir -p -- "$(dirname -- "$saved")"
    mv -- "$path" "$saved"
    log "Retired obsolete managed link $path; backup: $saved"
  else
    log "Would back up and retire obsolete managed link $path"
  fi
}

retire_obsolete_claude_commands() {
  local path="$HOME_DIR/.claude/commands"
  local managed="$REPO_DIR/claude/.claude/commands"
  local name

  [[ ! -e "$managed/reload.md" && ! -e "$managed/session-report.md" ]] || return 0

  if [[ -L "$path" ]]; then
    retire_managed_symlink "$path" "$managed" "claude/commands"
    return 0
  fi

  [[ -d "$path" ]] || return 0
  for name in reload.md session-report.md; do
    retire_managed_symlink \
      "$path/$name" \
      "$managed/$name" \
      "claude/commands/$name"
  done
}

retire_obsolete_claude_local_example() {
  local path="$HOME_DIR/.claude/settings.local.json.example"
  local managed="$REPO_DIR/claude/.claude/settings.local.json.example"

  [[ ! -e "$managed" ]] || return 0
  retire_managed_symlink "$path" "$managed" "claude/settings.local.json.example"
}

refuse_folded_root() {
  local path="$1"
  local managed="$2"
  local label="$3"
  local resolved

  [[ -L "$path" && -d "$path" ]] || return 0
  resolved=$(cd -- "$path" && pwd -P)
  [[ "$resolved" == "$managed" ]] || return 0

  warn "$path is a folded Stow link into the $label package: $managed"
  warn "Refusing to write through it because that would place runtime state in Git"
  warn "Back up runtime-only entries, unfold the package with Stow, then rerun this script"
  return 1
}

refuse_folded_roots() {
  refuse_folded_root "$HOME_DIR/.agents" "$REPO_DIR/ai/.agents" "shared AI"
  refuse_folded_root "$HOME_DIR/.claude" "$REPO_DIR/claude/.claude" "Claude"
  refuse_folded_root "$HOME_DIR/.codex" "$REPO_DIR/codex/.codex" "Codex"
}

validate_stow_package_sources() {
  local package
  local root
  local entry
  local relative
  local invalid=false

  for package in ai claude codex; do
    root="$REPO_DIR/$package"
    while IFS= read -r entry; do
      relative="${entry#"$root/"}"
      case "$package:$relative" in
        ai:.agents|ai:.agents/AGENTS.md|ai:.agents/skills|ai:.agents/skills/*)
          if [[ "$relative" != ".agents/skills/.antigravity-install-manifest.json" ]]; then
            continue
          fi
          ;;
        claude:.claude|claude:.claude/CLAUDE.md|claude:.claude/settings.json|claude:.claude/hooks|claude:.claude/hooks/lang-warmup.sh)
          continue
          ;;
        codex:.codex|codex:.codex/AGENTS.md|codex:.codex/hooks.json|codex:.codex/hooks|codex:.codex/hooks/lang-warmup.sh)
          continue
          ;;
      esac
      warn "Unexpected entry in the $package Stow package: $entry"
      invalid=true
    done < <(find "$root" -mindepth 1 -print)
  done

  if [[ "$invalid" == true ]]; then
    warn "Refusing to Stow package content outside the managed adapter allowlist"
    return 1
  fi
}

apply_stow() {
  log "Applying ai, claude, and codex Stow packages"
  stow --verbose=1 --no-folding \
    --dir="$REPO_DIR" --target="$HOME_DIR" ai claude codex
}

refuse_folded_roots
validate_stow_package_sources
preview_stow
inventory_skills
copy_singular_only_skills
migrate_language_state
migrate_language_warmup_preference
point_claude_to_canonical_skills
retire_obsolete_claude_commands
retire_obsolete_claude_local_example

if [[ "$apply" == true ]]; then
  apply_stow
  if [[ -n "$backup_dir" ]]; then
    log "Backups created under $backup_dir"
  fi
else
  log "Dry run complete; no HOME paths were changed. Re-run with --apply after review."
fi
