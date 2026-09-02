#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "NSX-T -> OpenShift policy demo preflight"
VERSION="$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || true)"
K8S="$(oc version -o json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("serverVersion",{}).get("gitVersion","unknown"))' 2>/dev/null || true)"
NETWORK="$(oc get network.operator.openshift.io cluster -o jsonpath='{.spec.defaultNetwork.type}' 2>/dev/null || true)"
POD_CIDR="$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.clusterNetwork[*].cidr}' 2>/dev/null || true)"
SVC_CIDR="$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.serviceNetwork[*]}' 2>/dev/null || true)"
MNP="$(oc get network.operator.openshift.io cluster -o jsonpath='{.spec.useMultiNetworkPolicy}' 2>/dev/null || true)"

echo "Lab server:           ${VERSION:-unknown}"
echo "Kubernetes:           ${K8S:-unknown}"
echo "Target compatibility: OpenShift $TARGET_OCP_VERSION"
echo "Network:              ${NETWORK:-unknown}"
echo "Pod CIDR:             ${POD_CIDR:-unknown}"
echo "Service CIDR:         ${SVC_CIDR:-unknown}"
echo "Demo CUDN:            192.0.2.0/24"
echo "MultiNetworkPolicy:   ${MNP:-false} (not required for main demo)"
echo "Workload policy plane: Primary CUDN + NetworkPolicy + real VMs"
echo "Admin policy plane:    dedicated default-network nsx-admin-* pods + ANP/BANP"
echo

case "$VERSION" in
  4.20.*) ok "Running directly on the target OpenShift 4.20 release" ;;
  4.21.*) ok "OpenShift 4.21 lab accepted; manifests use the 4.20 feature/API set used by this demo" ;;
  *) warn "Expected a 4.20 or 4.21 lab; detected '${VERSION:-unknown}'" ;;
esac
[[ "$NETWORK" == "OVNKubernetes" ]] && ok "Default network is OVN-Kubernetes" || { fail "This demo requires OVN-Kubernetes"; exit 1; }

for crd in \
  clusteruserdefinednetworks.k8s.ovn.org \
  adminnetworkpolicies.policy.networking.k8s.io \
  baselineadminnetworkpolicies.policy.networking.k8s.io \
  virtualmachines.kubevirt.io; do
  oc get crd "$crd" >/dev/null 2>&1 && ok "API/CRD available: $crd" || { fail "Missing required CRD: $crd"; exit 1; }
done

oc get hyperconverged -A >/dev/null 2>&1 && ok "OpenShift Virtualization detected" || { fail "OpenShift Virtualization is required"; exit 1; }

for resource in \
  clusteruserdefinednetworks.k8s.ovn.org \
  adminnetworkpolicies.policy.networking.k8s.io \
  baselineadminnetworkpolicies.policy.networking.k8s.io \
  networkpolicies.networking.k8s.io \
  namespaces \
  deployments.apps; do
  [[ "$(oc auth can-i create "$resource" 2>/dev/null)" == "yes" ]] && ok "Authorized to create: $resource" || { fail "Missing permission to create $resource"; exit 1; }
done

check_namespace_collisions || exit 1
ok "Existing demo namespace topology is compatible"

if oc get banp default >/dev/null 2>&1; then
  banp_owned_by_demo && warn "Demo BANP already exists" || warn "A non-demo BANP/default exists; demo.sh needs control of the BANP singleton"
else
  ok "No existing BANP/default"
fi

[[ "$(oc get anp --no-headers 2>/dev/null | wc -l | tr -d ' ')" == "0" ]] && ok "No existing AdminNetworkPolicy objects" || warn "Existing ANPs may influence traffic"

if oc get datasource "$RHEL9_DATASOURCE" -n "$RHEL9_DATASOURCE_NS" >/dev/null 2>&1; then
  ok "RHEL 9 boot source: $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"
else
  fail "RHEL 9 DataSource not found: $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"
  exit 1
fi

if oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null 2>&1; then
  ok "Windows 2022 boot source: $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"
else
  fail "Windows 2022 DataSource not found: $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"
  echo "Use ./scripts/import-windows-image.sh or ./scripts/register-windows-pvc.sh first."
  exit 1
fi

if oc get istag/network-tools:latest -n openshift >/dev/null 2>&1; then
  ok "OpenShift network-tools ImageStream available for probe pods"
else
  warn "network-tools ImageStream not found; set DEMO_IMAGE if the quay.io fallback is unavailable"
fi

info "Preflight complete"
