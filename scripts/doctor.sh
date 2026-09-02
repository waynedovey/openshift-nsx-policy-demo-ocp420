#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

echo "=== VM state ==="
"$ROOT_DIR/scripts/show-vms.sh" || true

echo
echo "=== CUDN ==="
oc get clusteruserdefinednetworks.k8s.ovn.org nsx-demo -o wide 2>/dev/null || true

echo
echo "=== Dedicated admin namespaces ==="
for ns in "${ADMIN_NAMESPACES[@]}"; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    printf '%-20s owner=%-16s primary-udn-label=' "$ns" "$(namespace_owner "$ns")"
    if namespace_has_primary_udn_label "$ns"; then echo "YES (ERROR)"; else echo "NO (correct)"; fi
  else
    echo "$ns MISSING"
  fi
done

echo
echo "=== Admin pods ==="
oc get pod -n nsx-admin-app -o wide --show-labels 2>/dev/null || true
oc get pod -n nsx-admin-corp -o wide --show-labels 2>/dev/null || true
oc get pod -n nsx-admin-ops -o wide --show-labels 2>/dev/null || true
oc get pod -n nsx-admin-rogue -o wide --show-labels 2>/dev/null || true

echo
echo "=== Policy objects ==="
oc get banp 2>/dev/null || true
oc get anp 2>/dev/null || true
oc get netpol -A 2>/dev/null | grep -E 'NAMESPACE|nsx-demo|nsx-admin' || true

echo
echo "=== Policy paths ==="
"$ROOT_DIR/scripts/show-policy-paths.sh" || true

TARGET="$(pod_default_ip nsx-admin-app app=admin-app-target 2>/dev/null || true)"
if [[ -n "$TARGET" ]]; then
  echo
echo "=== Admin target baseline connectivity (current policy state) ==="
  for item in \
    "nsx-admin-corp app=admin-corporate-client Corporate" \
    "nsx-admin-ops app=admin-jenkins-client Jenkins" \
    "nsx-admin-rogue app=admin-rogue-client Rogue"; do
    read -r ns label name <<<"$item"
    if can_connect "$ns" "$label" "$TARGET" 8443; then
      echo "$name -> $TARGET:8443 ALLOW"
    else
      echo "$name -> $TARGET:8443 DENY/UNREACHABLE"
    fi
  done
fi
