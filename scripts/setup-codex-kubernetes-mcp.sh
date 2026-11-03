#!/usr/bin/env bash
# Purpose: safely register one explicit Kubernetes MCP as global Codex config.
# The default mode is read-only; global configuration changes require --apply.
set -Eeuo pipefail

HOME_DIR="$(cd -- "${HOME:?HOME must be set}" && pwd -P)"
readonly HOME_DIR
readonly DEFAULT_PROFILE="$HOME_DIR/.codex/mcp-profiles/kubernetes-safe.toml"

apply=false
name=""
kubeconfig=""
server=""
profile="$DEFAULT_PROFILE"

usage() {
  cat <<'EOF'
Usage: scripts/setup-codex-kubernetes-mcp.sh \
  --name NAME --server PATH --kubeconfig PATH [--profile PATH] [--apply]

Preview or register a Kubernetes MCP in global Codex configuration. The
kubeconfig must contain exactly one context. Existing MCP entries are never
replaced automatically.

Options:
  --name NAME         Global Codex MCP server name.
  --server PATH       Version-pinned kubernetes-mcp-server executable.
  --kubeconfig PATH   Explicit single-context kubeconfig.
  --profile PATH      Safety profile (default: ~/.codex/mcp-profiles/kubernetes-safe.toml).
  --apply             Execute `codex mcp add`; without it, only preview.
  -h, --help          Show this help.
EOF
}

die() {
  printf 'setup-codex-kubernetes-mcp: %s\n' "$*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2:-}"

  [[ -n "$value" ]] || die "$option requires a value"
}

absolute_existing_path() {
  local path="$1"
  local directory
  local base

  directory=$(dirname -- "$path")
  base=$(basename -- "$path")
  directory=$(cd -- "$directory" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$directory" "$base"
}

while (($# > 0)); do
  case "$1" in
    --name)
      require_value "$1" "${2:-}"
      name="$2"
      shift 2
      ;;
    --server)
      require_value "$1" "${2:-}"
      server="$2"
      shift 2
      ;;
    --kubeconfig)
      require_value "$1" "${2:-}"
      kubeconfig="$2"
      shift 2
      ;;
    --profile)
      require_value "$1" "${2:-}"
      profile="$2"
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
  die "--name must match ^[A-Za-z0-9][A-Za-z0-9._-]*$"
[[ -n "$server" ]] || die "--server is required"
[[ -n "$kubeconfig" ]] || die "--kubeconfig is required"

for command_name in awk codex kubectl; do
  command -v "$command_name" >/dev/null 2>&1 || \
    die "required command not found: $command_name"
done

server=$(absolute_existing_path "$server") || die "server parent directory does not exist"
kubeconfig=$(absolute_existing_path "$kubeconfig") || die "kubeconfig parent directory does not exist"
profile=$(absolute_existing_path "$profile") || die "profile parent directory does not exist"

[[ -f "$server" && -x "$server" ]] || die "server is not an executable file: $server"
[[ -f "$kubeconfig" && -r "$kubeconfig" ]] || die "kubeconfig is not readable: $kubeconfig"
[[ -f "$profile" && -r "$profile" ]] || die "profile is not readable: $profile"

contexts=$(kubectl --kubeconfig "$kubeconfig" config get-contexts -o name) || \
  die "cannot read contexts from kubeconfig"
context_count=$(printf '%s\n' "$contexts" | awk 'NF { count++ } END { print count + 0 }')
[[ "$context_count" -eq 1 ]] || \
  die "kubeconfig must contain exactly one context; found $context_count"

current_context=$(kubectl --kubeconfig "$kubeconfig" config current-context) || \
  die "kubeconfig has no current context"
cluster_url=$(kubectl --kubeconfig "$kubeconfig" config view --minify \
  -o 'jsonpath={.clusters[0].cluster.server}') || die "cannot resolve cluster server URL"
[[ -n "$cluster_url" ]] || die "kubeconfig resolved an empty cluster server URL"

printf '[codex-mcp] name: %s\n' "$name"
printf '[codex-mcp] context: %s\n' "$current_context"
printf '[codex-mcp] cluster: %s\n' "$cluster_url"
printf '[codex-mcp] server: %s\n' "$server"
printf '[codex-mcp] profile: %s\n' "$profile"

if codex mcp get "$name" >/dev/null 2>&1; then
  die "MCP server '$name' already exists; review it and remove it explicitly before replacement"
fi

command=(
  codex mcp add "$name" --
  "$server"
  --config "$profile"
  --kubeconfig "$kubeconfig"
  --cluster-provider kubeconfig
  --disable-multi-cluster
)

printf '[codex-mcp] command:'
printf ' %q' "${command[@]}"
printf '\n'

if [[ "$apply" == false ]]; then
  printf '[codex-mcp] dry run only; repeat with --apply after reviewing the target above.\n'
  exit 0
fi

"${command[@]}"
printf '[codex-mcp] registered globally; restart Codex to load the new tools.\n'
