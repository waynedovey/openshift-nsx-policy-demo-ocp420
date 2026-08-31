#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "NSX-T -> OpenShift policy live demo"
echo "Lab: OpenShift 4.21.x | Target compatibility: OpenShift $TARGET_OCP_VERSION"
echo "Protected endpoints: Windows Server 2022 APP + Windows Server 2022 DB"
echo "Additional VM: RHEL 9 OPS"
echo
"$ROOT_DIR/scripts/show-vms.sh"
echo

"$ROOT_DIR/scripts/reset-policies.sh"
info "STAGE 0 — CUDN only: network exists, no firewall policy"
"$ROOT_DIR/scripts/test.sh" baseline
pause_demo

info "STAGE 1 — BANP baseline guardrail"
if oc get banp default >/dev/null 2>&1 && ! banp_owned_by_demo; then
  warn "Non-demo BANP/default exists; skipping this stage"
else
  oc apply -f "$ROOT_DIR/manifests/policies/10-banp-app-guardrail.yaml" >/dev/null
  sleep 3
  "$ROOT_DIR/scripts/test.sh" banp
fi
pause_demo

info "STAGE 2 — namespace NetworkPolicy overrides BANP"
oc apply -f "$ROOT_DIR/manifests/policies/20-networkpolicy-app.yaml" >/dev/null
sleep 2
if oc get banp default >/dev/null 2>&1 && banp_owned_by_demo; then "$ROOT_DIR/scripts/test.sh" app-np; else warn "BANP stage skipped; APP policy applied"; fi
pause_demo

info "STAGE 3 — DB namespace NetworkPolicy microsegmentation"
oc apply -f "$ROOT_DIR/manifests/policies/30-networkpolicy-db.yaml" >/dev/null
sleep 2
"$ROOT_DIR/scripts/test.sh" db-np
pause_demo

info "STAGE 4 — AdminNetworkPolicy: central DFW-style enforcement"
oc apply -f "$ROOT_DIR/manifests/policies/40-adminnetworkpolicy-db.yaml" >/dev/null
sleep 4
"$ROOT_DIR/scripts/test.sh" final

echo
info "Final policy objects"
oc get anp nsx-demo-db-security
oc get networkpolicy -n nsx-demo-app
oc get networkpolicy -n nsx-demo-db
oc get banp default 2>/dev/null || true

echo
ok "Demo complete"
