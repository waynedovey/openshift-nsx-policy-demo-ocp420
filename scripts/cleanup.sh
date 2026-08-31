#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

info "Cleaning up NSX policy demo"
"$ROOT_DIR/scripts/reset-policies.sh"
for ns in nsx-demo-app nsx-demo-db nsx-demo-ops nsx-demo-corp nsx-demo-rogue; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    owner="$(oc get ns "$ns" -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true)"
    if [[ "$owner" == "nsx-policy-demo" ]]; then oc delete ns "$ns" --wait=false >/dev/null; else warn "Leaving $ns untouched (not demo-owned)"; fi
  fi
done

for _ in $(seq 1 90); do
  remaining=0
  for ns in nsx-demo-app nsx-demo-db nsx-demo-ops nsx-demo-corp nsx-demo-rogue; do oc get ns "$ns" >/dev/null 2>&1 && remaining=$((remaining+1)); done
  [[ $remaining -eq 0 ]] && break
  sleep 2
done

if oc get cudn nsx-demo >/dev/null 2>&1; then
  owner="$(oc get cudn nsx-demo -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true)"
  [[ "$owner" == "nsx-policy-demo" ]] && oc delete cudn nsx-demo --ignore-not-found >/dev/null || warn "Leaving non-demo CUDN nsx-demo untouched"
fi
rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
ok "Demo namespaces, VMs, policies and local state removed"
warn "Reusable OS boot sources were intentionally left untouched"
