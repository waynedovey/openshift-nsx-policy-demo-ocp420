#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

APP_VM_IP="$(vm_ip nsx-demo-app win2022-app)"
DB_VM_IP="$(vm_ip nsx-demo-db win2022-db)"
APP_CUDN="$(pod_primary_ip nsx-demo-app app=app-probe 2>/dev/null || true)"
CORP_CUDN="$(pod_primary_ip nsx-demo-corp app=corporate-client 2>/dev/null || true)"
JENKINS_CUDN="$(pod_primary_ip nsx-demo-ops app=jenkins-probe 2>/dev/null || true)"
ROGUE_CUDN="$(pod_primary_ip nsx-demo-rogue app=rogue-client 2>/dev/null || true)"

ADMIN_TARGET="$(pod_default_ip nsx-admin-app app=admin-app-target 2>/dev/null || true)"
ADMIN_CORP="$(pod_default_ip nsx-admin-corp app=admin-corporate-client 2>/dev/null || true)"
ADMIN_JENKINS="$(pod_default_ip nsx-admin-ops app=admin-jenkins-client 2>/dev/null || true)"
ADMIN_ROGUE="$(pod_default_ip nsx-admin-rogue app=admin-rogue-client 2>/dev/null || true)"

echo "POLICY PLANES"
echo "-------------"
echo "Primary CUDN workload plane (NetworkPolicy)"
printf '  %-30s %s\n' "Windows APP" "${APP_VM_IP:-pending}"
printf '  %-30s %s\n' "Windows DB" "${DB_VM_IP:-pending}"
printf '  %-30s %s\n' "APP client" "${APP_CUDN:-pending}"
printf '  %-30s %s\n' "Corporate client" "${CORP_CUDN:-pending}"
printf '  %-30s %s\n' "Jenkins client" "${JENKINS_CUDN:-pending}"
printf '  %-30s %s\n' "Rogue client" "${ROGUE_CUDN:-pending}"
echo
echo "Dedicated cluster-default-network admin plane (ANP/BANP)"
printf '  %-30s %s\n' "Admin APP target" "${ADMIN_TARGET:-pending}"
printf '  %-30s %s\n' "Admin Corporate client" "${ADMIN_CORP:-pending}"
printf '  %-30s %s\n' "Admin Jenkins client" "${ADMIN_JENKINS:-pending}"
printf '  %-30s %s\n' "Admin Rogue client" "${ADMIN_ROGUE:-pending}"
echo
echo "IMPORTANT: infrastructure-locked 10.x addresses on Primary-CUDN pods are not"
echo "used as application endpoints. ANP/BANP use the dedicated nsx-admin-* pods."
