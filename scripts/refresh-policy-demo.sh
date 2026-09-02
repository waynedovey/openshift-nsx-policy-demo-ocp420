#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "Refreshing policy demo without recreating VMs"
check_namespace_collisions || exit 1
for ns in "${CUDN_NAMESPACES[@]}"; do
  oc get ns "$ns" >/dev/null 2>&1 || { fail "Missing existing workload namespace $ns. Run ./scripts/setup.sh for a fresh deployment."; exit 1; }
done
oc get clusteruserdefinednetworks.k8s.ovn.org nsx-demo >/dev/null 2>&1 || { fail "Missing CUDN nsx-demo. Run ./scripts/setup.sh for a fresh deployment."; exit 1; }
"$ROOT_DIR/scripts/reset-policies.sh"

info "Ensuring dedicated default-network admin-policy namespaces exist"
oc apply -f "$ROOT_DIR/manifests/base/03-admin-namespaces.yaml" >/dev/null

IMAGE="$(resolve_probe_image)"
info "Using probe image: $IMAGE"
TMP_CUDN_PROBES="$(mktemp)"
TMP_ADMIN_PROBES="$(mktemp)"
trap 'rm -f "$TMP_CUDN_PROBES" "$TMP_ADMIN_PROBES"' EXIT
sed "s|__DEMO_IMAGE__|$IMAGE|g" "$ROOT_DIR/manifests/base/02-probes.yaml.tpl" > "$TMP_CUDN_PROBES"
sed "s|__DEMO_IMAGE__|$IMAGE|g" "$ROOT_DIR/manifests/base/04-admin-probes.yaml.tpl" > "$TMP_ADMIN_PROBES"
oc apply -f "$TMP_CUDN_PROBES" >/dev/null
oc apply -f "$TMP_ADMIN_PROBES" >/dev/null
wait_for_probes
ok "CUDN clients and dedicated admin-policy probes updated"

ADMIN_TARGET_IP="$(wait_for_pod_ip default nsx-admin-app app=admin-app-target 120)" || { fail "Admin target default-network IP unavailable"; exit 1; }
info "Validating default-network admin-policy plane before applying policy"
wait_for_port nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 36 || {
  fail "Admin corporate client cannot reach $ADMIN_TARGET_IP:8443 with policies reset"
  echo "Run: ./scripts/doctor.sh"
  exit 1
}
wait_for_port nsx-admin-ops app=admin-jenkins-client "$ADMIN_TARGET_IP" 8443 12 || { fail "Admin Jenkins client cannot reach target baseline"; exit 1; }
wait_for_port nsx-admin-rogue app=admin-rogue-client "$ADMIN_TARGET_IP" 8443 12 || { fail "Admin Rogue client cannot reach target baseline"; exit 1; }
ok "Dedicated default-network policy plane is reachable"

echo
"$ROOT_DIR/scripts/show-policy-paths.sh"
echo
"$ROOT_DIR/scripts/test.sh" baseline

echo
ok "Existing VM environment is ready for the final demo"
echo "Run: ./scripts/demo.sh"
