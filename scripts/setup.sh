#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "Checking boot sources before changing the lab"
oc get datasource "$RHEL9_DATASOURCE" -n "$RHEL9_DATASOURCE_NS" >/dev/null || { fail "Missing RHEL9 DataSource $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"; exit 1; }
oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null || { fail "Missing Windows DataSource $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"; exit 1; }

info "Checking namespace name collisions"
for ns in nsx-demo-app nsx-demo-db nsx-demo-ops nsx-demo-corp nsx-demo-rogue; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    owner="$(oc get ns "$ns" -o jsonpath='{.metadata.labels.demo\.openshift\.io/owner}' 2>/dev/null || true)"
    [[ "$owner" == "nsx-policy-demo" ]] || { fail "Namespace $ns exists and is not owned by this demo"; exit 1; }
    oc get ns "$ns" -o json | grep -q 'k8s.ovn.org/primary-user-defined-network' || { fail "$ns was not created as a primary-UDN namespace"; exit 1; }
  fi
done

"$ROOT_DIR/scripts/reset-policies.sh"

info "Creating demo namespaces"
oc apply -f "$ROOT_DIR/manifests/base/00-namespaces.yaml" >/dev/null

info "Creating Primary Layer2 CUDN 192.0.2.0/24 with Persistent IPAM"
oc apply -f "$ROOT_DIR/manifests/base/01-cudn.yaml" >/dev/null
wait_for_cudn || { fail "CUDN did not become ready"; oc describe cudn nsx-demo || true; exit 1; }
ok "CUDN nsx-demo reports NetworkCreated=True"

if [[ -n "${DEMO_IMAGE:-}" ]]; then
  IMAGE="$DEMO_IMAGE"
elif oc get istag/network-tools:latest -n openshift >/dev/null 2>&1; then
  IMAGE="$(oc get istag/network-tools:latest -n openshift -o jsonpath='{.image.dockerImageReference}')"
else
  IMAGE="quay.io/openshift/origin-network-tools:latest"
fi
info "Using probe image: $IMAGE"
TMP_PROBES="$(mktemp)"
trap 'rm -f "$TMP_PROBES"' EXIT
sed "s|__DEMO_IMAGE__|$IMAGE|g" "$ROOT_DIR/manifests/base/02-probes.yaml.tpl" > "$TMP_PROBES"
oc apply -f "$TMP_PROBES" >/dev/null
wait_for_probes
ok "Probe workloads are ready"

info "Generating lab-only guest credentials and Windows sysprep"
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
APP_IP="$(wait_for_vm_ip nsx-demo-app win2022-app 300)" || { fail "Windows APP VMI did not report an IP. Check QEMU guest agent and NetKVM in the Windows golden image."; exit 1; }
DB_IP="$(wait_for_vm_ip nsx-demo-db win2022-db 300)" || { fail "Windows DB VMI did not report an IP. Check QEMU guest agent and NetKVM in the Windows golden image."; exit 1; }

info "Waiting for guest-side demo listeners"
wait_for_port nsx-demo-corp app=corporate-client "$APP_IP" 8443 240 || { fail "win2022-app did not open TCP/8443. Check sysprep FirstLogonCommands and Windows guest drivers."; exit 1; }
wait_for_port nsx-demo-app app=app-probe "$DB_IP" 1435 240 || { fail "win2022-db did not open TCP/1435. Check sysprep FirstLogonCommands and Windows guest drivers."; exit 1; }
wait_for_port nsx-demo-corp app=corporate-client "$RHEL_IP" 9090 120 || warn "RHEL9 TCP/9090 listener was not detected; core Windows policy demo can still run"

cat > "$STATE_DIR/ips.env" <<IPS
export WIN2022_APP_IP='$APP_IP'
export WIN2022_DB_IP='$DB_IP'
export RHEL9_OPS_IP='$RHEL_IP'
IPS
chmod 600 "$STATE_DIR/ips.env"

echo
"$ROOT_DIR/scripts/show-vms.sh"
echo
info "Baseline connectivity smoke test"
"$ROOT_DIR/scripts/test.sh" baseline

echo
ok "Demo environment deployed"
echo "Lab guest credentials are stored locally in: .demo-state/credentials.env"
echo "Run: ./scripts/demo.sh"
