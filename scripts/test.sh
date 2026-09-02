#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

STAGE="${1:-final}"
APP_IP="$(vm_ip nsx-demo-app win2022-app)"
DB_IP="$(vm_ip nsx-demo-db win2022-db)"
RHEL_IP="$(vm_ip nsx-demo-ops rhel9-ops)"
ADMIN_TARGET_IP="$(pod_default_ip nsx-admin-app app=admin-app-target 2>/dev/null || true)"

[[ -n "$APP_IP" && -n "$DB_IP" ]] || {
  fail "Could not find Windows VM CUDN IPs. Run ./scripts/setup.sh first."
  exit 1
}
[[ -n "$ADMIN_TARGET_IP" ]] || {
  fail "Could not find the dedicated default-network admin target. Run ./scripts/refresh-policy-demo.sh or ./scripts/setup.sh."
  exit 1
}

info "Testing stage: $STAGE"
echo "Windows APP CUDN:       $APP_IP"
echo "Windows DB CUDN:        $DB_IP"
echo "RHEL 9 OPS CUDN:        ${RHEL_IP:-pending}"
echo "Admin APP default-net:  $ADMIN_TARGET_IP"
echo

failures=0
run() { check_flow "$@" || failures=$((failures+1)); }

case "$STAGE" in
  baseline)
    # Real workload path on the Primary CUDN.
    run "CUDN Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 ALLOW
    run "CUDN APP -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    run "CUDN Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 ALLOW
    run "CUDN Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 ALLOW

    # Dedicated default-network admin-policy plane.
    run "ADMIN Corporate -> target:8443" nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 ALLOW
    run "ADMIN Jenkins -> target:8443" nsx-admin-ops app=admin-jenkins-client "$ADMIN_TARGET_IP" 8443 ALLOW
    run "ADMIN Rogue -> target:8443" nsx-admin-rogue app=admin-rogue-client "$ADMIN_TARGET_IP" 8443 ALLOW
    ;;

  banp)
    # BANP acts on dedicated default-network workloads.
    run "ADMIN Corporate -> target:8443" nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 DENY
    run "ADMIN Jenkins -> target:8443" nsx-admin-ops app=admin-jenkins-client "$ADMIN_TARGET_IP" 8443 DENY
    run "ADMIN Rogue -> target:8443" nsx-admin-rogue app=admin-rogue-client "$ADMIN_TARGET_IP" 8443 ALLOW

    # Primary CUDN is a separate policy plane in this validated demo.
    run "CUDN Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 ALLOW
    ;;

  app-np)
    # Standard NetworkPolicy provides real VM microsegmentation on the CUDN.
    run "CUDN Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 DENY
    run "CUDN APP -> WinAPP:8443" nsx-demo-app app=app-probe "$APP_IP" 8443 ALLOW

    # BANP remains independently active on the admin plane.
    run "ADMIN Corporate -> target:8443" nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 DENY
    ;;

  db-np)
    run "CUDN Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 DENY
    run "CUDN APP -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    run "CUDN APP -> WinDB:61435" nsx-demo-app app=app-probe "$DB_IP" 61435 ALLOW
    run "CUDN APP -> WinDB:8080" nsx-demo-app app=app-probe "$DB_IP" 8080 DENY
    run "CUDN Jenkins -> WinDB:1435" nsx-demo-ops app=jenkins-probe "$DB_IP" 1435 ALLOW
    run "CUDN Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 DENY
    run "CUDN Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 DENY
    ;;

  final)
    # ANP/BANP precedence on ordinary default-network-only workloads.
    run "ADMIN Corporate -> target:8443" nsx-admin-corp app=admin-corporate-client "$ADMIN_TARGET_IP" 8443 ALLOW
    run "ADMIN Rogue -> target:8443" nsx-admin-rogue app=admin-rogue-client "$ADMIN_TARGET_IP" 8443 DENY
    run "ADMIN Jenkins -> target:8443" nsx-admin-ops app=admin-jenkins-client "$ADMIN_TARGET_IP" 8443 DENY

    # Real Windows CUDN microsegmentation remains in force simultaneously.
    run "CUDN Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 DENY
    run "CUDN APP -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    run "CUDN APP -> WinDB:61435" nsx-demo-app app=app-probe "$DB_IP" 61435 ALLOW
    run "CUDN APP -> WinDB:8080" nsx-demo-app app=app-probe "$DB_IP" 8080 DENY
    run "CUDN Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 DENY
    run "CUDN Jenkins -> WinDB:1435" nsx-demo-ops app=jenkins-probe "$DB_IP" 1435 ALLOW
    run "CUDN Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 DENY
    ;;

  *)
    echo "Usage: $0 {baseline|banp|app-np|db-np|final}" >&2
    exit 2
    ;;
esac

echo
(( failures == 0 )) && ok "All $STAGE expectations matched" || {
  fail "$failures expectation(s) did not match"
  exit 1
}
