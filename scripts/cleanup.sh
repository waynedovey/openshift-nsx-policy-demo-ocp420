#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

CUDN_RESOURCE='clusteruserdefinednetworks.k8s.ovn.org'
ALL_NAMESPACES=("${CUDN_NAMESPACES[@]}" "${ADMIN_NAMESPACES[@]}")

info "Cleaning up NSX policy demo"
"$ROOT_DIR/scripts/reset-policies.sh"

info "Stopping/removing demo workloads"
for ns in "${ALL_NAMESPACES[@]}"; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    owner="$(namespace_owner "$ns")"
    if [[ "$owner" == "nsx-policy-demo" ]]; then
      oc delete vm --all -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      oc delete deployment --all -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    else
      warn "Leaving $ns untouched (not demo-owned)"
    fi
  fi
done

# Wait for CUDN-attached workloads to disappear before deleting the CUDN.
for _ in $(seq 1 90); do
  active=0
  for ns in "${CUDN_NAMESPACES[@]}"; do
    if oc get ns "$ns" >/dev/null 2>&1; then
      vmis="$(oc get vmi -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
      pods="$(oc get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
      (( active += vmis + pods )) || true
    fi
  done
  [[ $active -eq 0 ]] && break
  sleep 2
done

info "Deleting demo CUDN before its Primary-UDN namespaces"
if oc get "$CUDN_RESOURCE" nsx-demo >/dev/null 2>&1; then
  owner="$(oc get "$CUDN_RESOURCE" nsx-demo -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true)"
  if [[ "$owner" == "nsx-policy-demo" ]]; then
    oc delete "$CUDN_RESOURCE" nsx-demo --wait=true --timeout=240s >/dev/null
  else
    warn "Leaving non-demo CUDN nsx-demo untouched"
  fi
fi

for _ in $(seq 1 90); do
  oc get network-attachment-definitions.k8s.cni.cncf.io -A --no-headers 2>/dev/null | awk '$2=="nsx-demo"{found=1} END{exit found?0:1}' && sleep 2 || break
done

info "Deleting demo namespaces"
for ns in "${ALL_NAMESPACES[@]}"; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    owner="$(namespace_owner "$ns")"
    [[ "$owner" == "nsx-policy-demo" ]] && oc delete ns "$ns" --wait=false >/dev/null || true
  fi
done

for _ in $(seq 1 120); do
  remaining=0
  for ns in "${ALL_NAMESPACES[@]}"; do
    oc get ns "$ns" >/dev/null 2>&1 && remaining=$((remaining+1))
  done
  [[ $remaining -eq 0 ]] && break
  sleep 2
done

rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
ok "Demo workloads, CUDN, namespaces, policies and local state removed"
warn "Reusable OS boot sources were intentionally left untouched"
