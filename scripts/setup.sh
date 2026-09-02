#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "Checking boot sources before changing the lab"
oc get datasource "$RHEL9_DATASOURCE" -n "$RHEL9_DATASOURCE_NS" >/dev/null || { fail "Missing RHEL9 DataSource $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"; exit 1; }
oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null || { fail "Missing Windows DataSource $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"; exit 1; }

info "Checking namespace name collisions"
check_namespace_collisions || exit 1

"$ROOT_DIR/scripts/reset-policies.sh"

info "Creating Primary-CUDN workload namespaces"
oc apply -f "$ROOT_DIR/manifests/base/00-namespaces.yaml" >/dev/null

info "Creating dedicated default-network admin-policy namespaces"
oc apply -f "$ROOT_DIR/manifests/base/03-admin-namespaces.yaml" >/dev/null

info "Creating Primary Layer2 CUDN 192.0.2.0/24 with Persistent IPAM"
oc apply -f "$ROOT_DIR/manifests/base/01-cudn.yaml" >/dev/null
wait_for_cudn || { fail "CUDN did not become ready"; oc describe clusteruserdefinednetworks.k8s.ovn.org nsx-demo || true; exit 1; }
ok "CUDN nsx-demo reports NetworkCreated=True"

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
ok "CUDN client probes and dedicated admin-policy probes are ready"

ADMIN_TARGET_IP="$(wait_for_pod_ip default nsx-admin-app app=admin-app-target 120)" || { fail "Admin target did not report a default-network IP"; exit 1; }
info "Checking dedicated default-network admin target TCP/8443"
wait_for_port nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 36 || {
  fail "Admin target $ADMIN_TARGET_IP:8443 is not reachable before policy. Check nsx-admin-* pods."
  exit 1
}
ok "Dedicated admin-policy plane is reachable before policy"

info "Generating guest credentials and Windows sysprep media"
ensure_demo_password
"$ROOT_DIR/scripts/render-sysprep.sh"

render_vm() {
  local src="$1" dst="$2"
  sed \
    -e "s|__RHEL9_DATASOURCE__|$RHEL9_DATASOURCE|g" \
    -e "s|__RHEL9_DATASOURCE_NS__|$RHEL9_DATASOURCE_NS|g" \
    -e "s|__WINDOWS_DATASOURCE__|$WINDOWS_DATASOURCE|g" \
    -e "s|__WINDOWS_DATASOURCE_NS__|$WINDOWS_DATASOURCE_NS|g" \
    -e "s|__WINDOWS_MEMORY__|$WINDOWS_MEMORY|g" \
    -e "s|__WINDOWS_CORES__|$WINDOWS_CORES|g" \
    -e "s|__RHEL_MEMORY__|$RHEL_MEMORY|g" \
    -e "s|__RHEL_CORES__|$RHEL_CORES|g" \
    -e "s|__DEMO_PASSWORD__|$DEMO_ADMIN_PASSWORD|g" \
    "$src" > "$dst"
}

info "Deploying RHEL 9 x1 and Windows Server 2022 x2"
for spec in \
  "10-rhel9-ops.yaml.tpl:rhel9.yaml" \
  "11-win2022-app.yaml.tpl:winapp.yaml" \
  "12-win2022-db.yaml.tpl:windb.yaml"; do
  src="${spec%%:*}"; out="${spec##*:}"
  render_vm "$ROOT_DIR/manifests/vms/$src" "$STATE_DIR/$out"
  oc apply -f "$STATE_DIR/$out" >/dev/null
done

info "Waiting for VMs (initial clone/first boot can take several minutes)"
wait_for_vm_ready nsx-demo-ops rhel9-ops 20m
wait_for_vm_ready nsx-demo-app win2022-app 30m
wait_for_vm_ready nsx-demo-db win2022-db 30m
ok "All three VirtualMachine objects report Ready=True"

RHEL_IP="$(wait_for_vm_ip nsx-demo-ops rhel9-ops 300)" || { fail "RHEL9 VMI did not report an IP"; exit 1; }
APP_IP="$(wait_for_vm_ip nsx-demo-app win2022-app 300)" || { fail "Windows APP VMI did not report an IP. Check QEMU guest agent."; exit 1; }
DB_IP="$(wait_for_vm_ip nsx-demo-db win2022-db 300)" || { fail "Windows DB VMI did not report an IP. Check QEMU guest agent."; exit 1; }

info "Waiting for guest-side demo listeners"
wait_for_port nsx-demo-corp app=corporate-client "$APP_IP" 8443 240 || { fail "win2022-app did not open TCP/8443"; "$ROOT_DIR/scripts/check-windows-bootstrap.sh" || true; exit 1; }
wait_for_port nsx-demo-app app=app-probe "$DB_IP" 1435 240 || { fail "win2022-db did not open TCP/1435"; "$ROOT_DIR/scripts/check-windows-bootstrap.sh" || true; exit 1; }
wait_for_port nsx-demo-corp app=corporate-client "$RHEL_IP" 9090 120 || warn "RHEL9 TCP/9090 listener was not detected; core Windows policy demo can still run"

cat > "$STATE_DIR/ips.env" <<IPS
export WIN2022_APP_IP='$APP_IP'
export WIN2022_DB_IP='$DB_IP'
export RHEL9_OPS_IP='$RHEL_IP'
export ADMIN_APP_TARGET_IP='$ADMIN_TARGET_IP'
IPS
chmod 600 "$STATE_DIR/ips.env"

echo
"$ROOT_DIR/scripts/show-vms.sh"
echo
"$ROOT_DIR/scripts/show-policy-paths.sh"
echo
info "Baseline connectivity smoke test"
"$ROOT_DIR/scripts/test.sh" baseline

echo
ok "Demo environment deployed"
echo "RHEL demo credentials are stored locally in: .demo-state/credentials.env"
echo "Windows Administrator uses a generated lab-only password with AutoLogon."
echo "Run: ./scripts/demo.sh"
