#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.demo-state"
mkdir -p "$STATE_DIR"

CUDN_NAMESPACES=(nsx-demo-app nsx-demo-db nsx-demo-ops nsx-demo-corp nsx-demo-rogue)
ADMIN_NAMESPACES=(nsx-admin-app nsx-admin-corp nsx-admin-ops nsx-admin-rogue)

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
  export WINDOWS_DATASOURCE="${WINDOWS_DATASOURCE:-win2022-demo-v2}"
  export WINDOWS_DATASOURCE_NS="${WINDOWS_DATASOURCE_NS:-openshift-virtualization-os-images}"
  export WINDOWS_MEMORY="${WINDOWS_MEMORY:-4Gi}"
  export WINDOWS_CORES="${WINDOWS_CORES:-2}"
  export WINDOWS_STORAGE_CLASS="${WINDOWS_STORAGE_CLASS:-ocs-external-storagecluster-ceph-rbd}"
  export WINDOWS_IMAGE_SIZE="${WINDOWS_IMAGE_SIZE:-70Gi}"
  export RHEL_MEMORY="${RHEL_MEMORY:-2Gi}"
  export RHEL_CORES="${RHEL_CORES:-2}"
}

namespace_owner() {
  oc get ns "$1" -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true
}

namespace_has_primary_udn_label() {
  oc get ns "$1" -o json 2>/dev/null | grep -q '"k8s.ovn.org/primary-user-defined-network"'
}

check_namespace_collisions() {
  local ns owner
  for ns in "${CUDN_NAMESPACES[@]}"; do
    if oc get ns "$ns" >/dev/null 2>&1; then
      owner="$(namespace_owner "$ns")"
      [[ "$owner" == "nsx-policy-demo" ]] || { fail "Namespace $ns exists and is not owned by this demo"; return 1; }
      namespace_has_primary_udn_label "$ns" || { fail "$ns exists but is not a Primary-UDN namespace"; return 1; }
    fi
  done

  for ns in "${ADMIN_NAMESPACES[@]}"; do
    if oc get ns "$ns" >/dev/null 2>&1; then
      owner="$(namespace_owner "$ns")"
      [[ "$owner" == "nsx-policy-demo" ]] || { fail "Namespace $ns exists and is not owned by this demo"; return 1; }
      if namespace_has_primary_udn_label "$ns"; then
        fail "$ns incorrectly has k8s.ovn.org/primary-user-defined-network; admin-policy namespaces must remain on the cluster default network"
        return 1
      fi
    fi
  done
}

resolve_probe_image() {
  if [[ -n "${DEMO_IMAGE:-}" ]]; then
    echo "$DEMO_IMAGE"
  elif oc get istag/network-tools:latest -n openshift >/dev/null 2>&1; then
    oc get istag/network-tools:latest -n openshift -o jsonpath='{.image.dockerImageReference}'
  else
    echo "quay.io/openshift/origin-network-tools:latest"
  fi
}

pod_name() {
  local ns="$1" label="$2"
  oc get pod -n "$ns" -l "$label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

vm_ip() {
  local ns="$1" vm="$2"
  oc get vmi "$vm" -n "$ns" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || true
}

pod_default_ip() {
  local ns="$1" label="$2"
  local pod
  pod="$(pod_name "$ns" "$label")"
  [[ -n "$pod" ]] || return 1
  oc get pod "$pod" -n "$ns" -o jsonpath='{.status.podIP}' 2>/dev/null
}

pod_primary_ip() {
  local ns="$1" label="$2"
  local pod json
  pod="$(pod_name "$ns" "$label")"
  [[ -n "$pod" ]] || return 1
  json="$(oc get pod "$pod" -n "$ns" -o jsonpath='{.metadata.annotations.k8s\.ovn\.org/pod-networks}' 2>/dev/null || true)"
  [[ -n "$json" ]] || return 1
  python3 -c 'import json,sys; d=json.load(sys.stdin); vals=[v for v in d.values() if v.get("role")=="primary"]; print(vals[0].get("ip_addresses",[vals[0].get("ip_address","")])[0].split("/")[0] if vals else "")' <<<"$json"
}

wait_for_pod_ip() {
  local mode="$1" ns="$2" label="$3" tries="${4:-120}"
  local ip=""
  while (( tries > 0 )); do
    if [[ "$mode" == "default" ]]; then
      ip="$(pod_default_ip "$ns" "$label" 2>/dev/null || true)"
    else
      ip="$(pod_primary_ip "$ns" "$label" 2>/dev/null || true)"
    fi
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    sleep 2
    ((tries--))
  done
  return 1
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
  local tries=90 status
  while (( tries > 0 )); do
    status="$(oc get clusteruserdefinednetworks.k8s.ovn.org nsx-demo -o jsonpath='{range .status.conditions[?(@.type=="NetworkCreated")]}{.status}{end}' 2>/dev/null || true)"
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
    "nsx-admin-app admin-app-target"
    "nsx-admin-corp admin-corporate-client"
    "nsx-admin-ops admin-jenkins-client"
    "nsx-admin-rogue admin-rogue-client"
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
  local src_ns="$1" src_label="$2" dst_ip="$3" dst_port="$4" tries="${5:-60}"
  local elapsed=0
  while (( tries > 0 )); do
    can_connect "$src_ns" "$src_label" "$dst_ip" "$dst_port" && return 0
    sleep 5
    ((tries--))
    ((elapsed+=5))
    if (( elapsed % 60 == 0 )); then
      warn "Still waiting for $dst_ip:$dst_port (${elapsed}s elapsed)"
    fi
  done
  return 1
}

check_flow() {
  local label="$1" src_ns="$2" src_label="$3" dst_ip="$4" dst_port="$5" expected="$6"
  local rc=0 actual="DENY"
  can_connect "$src_ns" "$src_label" "$dst_ip" "$dst_port" || rc=$?
  [[ $rc -eq 0 ]] && actual="ALLOW"
  if [[ "$actual" == "$expected" ]]; then
    ok "$(printf '%-46s' "$label") expected=$expected actual=$actual"
    return 0
  fi
  fail "$(printf '%-46s' "$label") expected=$expected actual=$actual"
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
      fail "DEMO_ADMIN_PASSWORD contains characters unsafe for this lab template. Use letters, numbers, and . _ ! @ # % + = : - only."
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
