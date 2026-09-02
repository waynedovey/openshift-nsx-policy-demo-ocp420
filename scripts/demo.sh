#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "NSX-T -> OpenShift policy live demo"
echo "Lab: OpenShift 4.21.x | Target compatibility: OpenShift $TARGET_OCP_VERSION"
echo "Workload plane: Primary Layer2 CUDN + real Windows VMs + NetworkPolicy"
echo "Admin plane: dedicated cluster-default-network pods + ANP/BANP"
echo
"$ROOT_DIR/scripts/show-vms.sh"
echo
"$ROOT_DIR/scripts/show-policy-paths.sh"
echo

# Fail fast if the dedicated admin policy plane has not been installed/refreshed.
for ns in "${ADMIN_NAMESPACES[@]}"; do
  oc get ns "$ns" >/dev/null 2>&1 || {
    fail "Missing $ns. Run ./scripts/refresh-policy-demo.sh first."
    exit 1
  }
  namespace_has_primary_udn_label "$ns" && {
    fail "$ns has the Primary UDN label. Admin namespaces must be default-network-only."
    exit 1
  }
done

"$ROOT_DIR/scripts/reset-policies.sh"
info "STAGE 0 — Network topology only: no firewall policy"
echo "NSX Segment -> Primary Layer2 CUDN for VM workloads."
echo "A separate default-network-only policy plane is used to demonstrate ANP/BANP."
"$ROOT_DIR/scripts/test.sh" baseline
pause_demo

info "STAGE 1 — BANP baseline guardrail on the dedicated admin plane"
echo "Corporate and Jenkins are denied to admin-app-target:8443; Rogue remains allowed."
if oc get banp default >/dev/null 2>&1 && ! banp_owned_by_demo; then
  fail "A non-demo BANP/default exists. BANP is a singleton; preserve/remove it outside this lab before running Stage 1."
  exit 1
fi
oc apply -f "$ROOT_DIR/manifests/policies/10-banp-app-guardrail.yaml" >/dev/null
sleep 5
"$ROOT_DIR/scripts/test.sh" banp
pause_demo

info "STAGE 2 — NetworkPolicy: real Windows APP microsegmentation on the Primary CUDN"
echo "Corporate -> WinAPP:8443 becomes DENY; APP-group traffic remains ALLOW."
oc apply -f "$ROOT_DIR/manifests/policies/20-networkpolicy-app.yaml" >/dev/null
sleep 4
"$ROOT_DIR/scripts/test.sh" app-np
pause_demo

info "STAGE 3 — NetworkPolicy: real Windows DB microsegmentation on the Primary CUDN"
echo "APP receives SQL/MSDTC-style ports; Jenkins receives only 1435; Rogue is denied."
oc apply -f "$ROOT_DIR/manifests/policies/30-networkpolicy-db.yaml" >/dev/null
sleep 4
"$ROOT_DIR/scripts/test.sh" db-np
pause_demo

info "STAGE 4 — AdminNetworkPolicy: mandatory admin tier + BANP precedence"
echo "Corporate ANP Allow overrides BANP Deny."
echo "Rogue ANP Deny is authoritative."
echo "Jenkins ANP Pass delegates to BANP, where it is denied."
oc apply -f "$ROOT_DIR/manifests/policies/40-adminnetworkpolicy-default-network.yaml" >/dev/null
sleep 6
"$ROOT_DIR/scripts/test.sh" final

echo
info "Final policy objects"
oc get anp nsx-demo-admin-guardrail
oc get networkpolicy -n nsx-demo-app
oc get networkpolicy -n nsx-demo-db
oc get banp default 2>/dev/null || true

echo
ok "Demo complete"
