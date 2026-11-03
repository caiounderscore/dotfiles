#!/usr/bin/env zsh

set -u

readonly REPO_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-kprod-test.XXXXXX")"
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Resolved from this script's physical repository path.
# shellcheck disable=SC1091
source "$REPO_DIR/zsh/.aliases"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_caller_kubeconfig() {
  [[ "$KUBECONFIG" == "$CALLER_KUBECONFIG" ]] ||
    fail "kprod changed the caller KUBECONFIG"
}

assert_logged() {
  local expected="$1"
  grep -F -- "$expected" "$TEST_ROOT/kubectl.log" >/dev/null ||
    fail "kubectl log did not contain: $expected"
}

logged_command_count() {
  wc -l < "$TEST_ROOT/kubectl.log" | tr -d ' '
}

assert_mutating_confirmation() {
  local label="$1"
  shift
  local before after

  before=$(logged_command_count)
  if kprod "$@" <<< "no" >"$TEST_ROOT/$label.no" 2>&1; then
    fail "$label ran without explicit confirmation"
  fi
  after=$(logged_command_count)
  [[ "$after" == "$before" ]] || fail "$label invoked kubectl after confirmation was denied"

  kprod "$@" <<< "yes" >"$TEST_ROOT/$label.yes" 2>&1 ||
    fail "$label did not run after explicit confirmation"
  after=$(logged_command_count)
  [[ "$after" == $((before + 1)) ]] || fail "$label did not invoke kubectl exactly once"
  assert_caller_kubeconfig
}

export K8S_PROD_CONTEXT="bladecp-production"
export K8S_PROD_KUBECONFIG="$TEST_ROOT/production-kubeconfig"
export K8S_PROD_API_HOST="192.0.2.10"
touch -- "$K8S_PROD_KUBECONFIG"

kubectl() {
  if [[ "$*" == "--kubeconfig $K8S_PROD_KUBECONFIG config current-context" ]]; then
    print -- "$K8S_PROD_CONTEXT"
    return 0
  fi
  print -r -- "${KUBECONFIG-}\t$*" >> "$TEST_ROOT/kubectl.log"
}

nc() {
  return 0
}

export KUBECONFIG="$TEST_ROOT/caller-kubeconfig"
readonly CALLER_KUBECONFIG="$KUBECONFIG"
: > "$TEST_ROOT/kubectl.log"

kprod get pods >/dev/null || fail "read-only get failed"
kprod list pods >/dev/null || fail "read-only list failed"
kprod describe pod example >/dev/null || fail "read-only describe failed"
kprod logs pod/example >/dev/null || fail "read-only logs failed"
assert_logged "$K8S_PROD_KUBECONFIG\tget pods"
assert_logged "$K8S_PROD_KUBECONFIG\tlist pods"
assert_logged "$K8S_PROD_KUBECONFIG\tdescribe pod example"
assert_logged "$K8S_PROD_KUBECONFIG\tlogs pod/example"
assert_caller_kubeconfig

assert_mutating_confirmation delete delete pod example
assert_mutating_confirmation apply apply -f deployment.yaml
assert_mutating_confirmation patch patch deployment example --type merge -p '{}'
assert_mutating_confirmation edit edit deployment example
assert_mutating_confirmation scale scale deployment example --replicas 2
assert_mutating_confirmation rollout-restart rollout restart deployment/example

kprod -n production get pods >/dev/null || fail "read-only get with -n failed"
kprod --namespace production describe pod example >/dev/null ||
  fail "read-only describe with --namespace failed"
kprod --context "$K8S_PROD_CONTEXT" logs pod/example >/dev/null ||
  fail "read-only logs with --context failed"
assert_mutating_confirmation flagged-delete -n production delete pod example
assert_mutating_confirmation flagged-patch --namespace=production patch deployment example -p '{}'
assert_mutating_confirmation flagged-rollout --context "$K8S_PROD_CONTEXT" rollout restart deployment/example

before=$(logged_command_count)
if kprod --unknown value get pods >"$TEST_ROOT/ambiguous-flag" 2>&1; then
  fail "unknown leading flag did not fail closed"
fi
if kprod frobnicate >"$TEST_ROOT/ambiguous-operation" 2>&1; then
  fail "unknown operation did not fail closed"
fi
if kprod --context other-context get pods >"$TEST_ROOT/context-override" 2>&1; then
  fail "production context override did not fail closed"
fi
if kprod --kubeconfig other-config get pods >"$TEST_ROOT/kubeconfig-override" 2>&1; then
  fail "production kubeconfig override did not fail closed"
fi
if kprod get pods --context other-context >"$TEST_ROOT/trailing-context-override" 2>&1; then
  fail "trailing production context override did not fail closed"
fi
if kprod get pods --kubeconfig other-config >"$TEST_ROOT/trailing-kubeconfig-override" 2>&1; then
  fail "trailing production kubeconfig override did not fail closed"
fi
[[ "$(logged_command_count)" == "$before" ]] ||
  fail "ambiguous command invoked kubectl"
assert_caller_kubeconfig

unset K8S_PROD_API_HOST
if kprod get pods >"$TEST_ROOT/missing-api-host" 2>&1; then
  fail "kprod without K8S_PROD_API_HOST did not fail closed"
fi
if kprodtalos >"$TEST_ROOT/talos-missing-api-host" 2>&1; then
  fail "kprodtalos without the local production endpoint did not fail closed"
fi
[[ "$(logged_command_count)" == "$before" ]] ||
  fail "missing production endpoint invoked kubectl"
assert_caller_kubeconfig

print -- "PASS: kprod safety"
