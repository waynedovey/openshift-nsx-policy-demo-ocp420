#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.demo-state"
mkdir -p "$STATE_DIR"

if [[ -t 1 ]]; then
  BOLD='\033[1m'; GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; BLUE='\033[34m'; RESET='\033[0m'
else
  BOLD=''; GREEN=''; RED=''; YELLOW=''; BLUE=''; RESET=''
fi

info() { printf "%b\n" "${BLUE}${BOLD}==>${RESET} $*"; }
ok()   { printf "%b\n" "${GREEN}PASS${RESET} $*"; }
warn() { printf "%b\n" "${YELLOW}WARN${RESET} $*"; }
fail() { printf "%b\n" "${RED}FAIL${RESET} $*" >&2; }

require_oc() {
  command -v oc >/dev/null 2>&1 || { fail "oc was not found in PATH"; exit 1; }
  oc whoami >/dev/null 2>&1 || { fail "Not logged in to an OpenShift cluster"; exit 1; }
}

load_config() {
  # shellcheck disable=SC1091
  [[ -f "$ROOT_DIR/config/lab.env" ]] && source "$ROOT_DIR/config/lab.env"
  export TARGET_OCP_VERSION="${TARGET_OCP_VERSION:-4.20}"
  export RHEL9_DATASOURCE="${RHEL9_DATASOURCE:-rhel9}"
  export RHEL9_DATASOURCE_NS="${RHEL9_DATASOURCE_NS:-openshift-virtualization-os-images}"
  export WINDOWS_DATASOURCE="${WINDOWS_DATASOURCE:-win2022-demo}"
  export WINDOWS_DATASOURCE_NS="${WINDOWS_DATASOURCE_NS:-openshift-virtualization-os-images}"
  export WINDOWS_MEMORY="${WINDOWS_MEMORY:-4Gi}"
  export WINDOWS_CORES="${WINDOWS_CORES:-2}"
  export RHEL_MEMORY="${RHEL_MEMORY:-2Gi}"
  export RHEL_CORES="${RHEL_CORES:-2}"
}

pod_name() {
  local ns="$1" label="$2"
  oc get pod -n "$ns" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

vm_ip() {
  local ns="$1" vm="$2"
  oc get vmi "$vm" -n "$ns" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || true
}

wait_for_vm_ip() {
  local ns="$1" vm="$2" tries="${3:-300}"
  local ip=""
  while (( tries > 0 )); do
    ip="$(vm_ip "$ns" "$vm")"
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    sleep 2
    ((tries--))
  done
  return 1
}

wait_for_vm_ready() {
  local ns="$1" vm="$2" timeout="${3:-20m}"
  oc wait -n "$ns" "vm/$vm" --for=condition=Ready --timeout="$timeout" >/dev/null
}

wait_for_cudn() {
  local tries=90
  while (( tries > 0 )); do
    local status
    status="$(oc get clusteruserdefinednetwork nsx-demo -o jsonpath='{range .status.conditions[?(@.type=="NetworkCreated")]}{.status}{end}' 2>/dev/null || true)"
    [[ "$status" == "True" ]] && return 0
    sleep 2
    ((tries--))
  done
  return 1
}

wait_for_probes() {
  local items=(
    "nsx-demo-app app-probe"
    "nsx-demo-ops jenkins-probe"
    "nsx-demo-corp corporate-client"
    "nsx-demo-rogue rogue-client"
  )
  local item ns deploy
  for item in "${items[@]}"; do
    read -r ns deploy <<<"$item"
    oc rollout status "deployment/$deploy" -n "$ns" --timeout=180s >/dev/null
  done
}

can_connect() {
  local src_ns="$1" src_label="$2" dst_ip="$3" dst_port="$4"
  local src_pod
  src_pod="$(pod_name "$src_ns" "$src_label")"
  [[ -n "$src_pod" && -n "$dst_ip" ]] || return 2
  oc exec -n "$src_ns" "$src_pod" -- /bin/sh -c "nc -z -w 3 '$dst_ip' '$dst_port'" >/dev/null 2>&1
}

wait_for_port() {
  local src_ns="$1" src_label="$2" dst_ip="$3" dst_port="$4" tries="${5:-240}"
  while (( tries > 0 )); do
    can_connect "$src_ns" "$src_label" "$dst_ip" "$dst_port" && return 0
    sleep 5
    ((tries--))
  done
  return 1
}

check_flow() {
  local label="$1" src_ns="$2" src_label="$3" dst_ip="$4" dst_port="$5" expected="$6"
  local rc=0
  can_connect "$src_ns" "$src_label" "$dst_ip" "$dst_port" || rc=$?
  local actual="DENY"
  [[ $rc -eq 0 ]] && actual="ALLOW"
  if [[ "$actual" == "$expected" ]]; then
    ok "$(printf '%-36s' "$label") expected=$expected actual=$actual"
    return 0
  fi
  fail "$(printf '%-36s' "$label") expected=$expected actual=$actual"
  return 1
}

pause_demo() {
  [[ "${DEMO_AUTO:-false}" == "true" ]] && return 0
  printf "\nPress Enter to continue... "
  read -r _
}

banp_owned_by_demo() {
  [[ "$(oc get banp default -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true)" == "nsx-policy-demo" ]]
}

ensure_demo_password() {
  local credfile="$STATE_DIR/credentials.env"
  if [[ -n "${DEMO_ADMIN_PASSWORD:-}" ]]; then
    if [[ ! "$DEMO_ADMIN_PASSWORD" =~ ^[A-Za-z0-9._!@#%+=:-]+$ ]]; then
      fail "DEMO_ADMIN_PASSWORD contains characters that are unsafe for this lab template. Use letters, numbers, and . _ ! @ # % + = : - only."
      exit 1
    fi
    printf "export DEMO_ADMIN_PASSWORD='%s'\n" "$DEMO_ADMIN_PASSWORD" > "$credfile"
    chmod 600 "$credfile"
    return 0
  fi
  if [[ -f "$credfile" ]]; then
    # shellcheck disable=SC1090
    source "$credfile"
    export DEMO_ADMIN_PASSWORD
    return 0
  fi
  local token
  if command -v openssl >/dev/null 2>&1; then token="$(openssl rand -hex 6)"; else token="$(date +%s)Aa9"; fi
  DEMO_ADMIN_PASSWORD="Demo-${token}!Aa9"
  export DEMO_ADMIN_PASSWORD
  printf "export DEMO_ADMIN_PASSWORD='%s'\n" "$DEMO_ADMIN_PASSWORD" > "$credfile"
  chmod 600 "$credfile"
}
