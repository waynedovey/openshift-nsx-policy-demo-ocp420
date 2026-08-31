#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

STAGE="${1:-final}"
APP_IP="$(vm_ip nsx-demo-app win2022-app)"
DB_IP="$(vm_ip nsx-demo-db win2022-db)"
RHEL_IP="$(vm_ip nsx-demo-ops rhel9-ops)"
[[ -n "$APP_IP" && -n "$DB_IP" ]] || { fail "Could not find Windows VM CUDN IPs. Run ./scripts/setup.sh first."; exit 1; }

info "Testing stage: $STAGE"
echo "Windows APP: $APP_IP"
echo "Windows DB:  $DB_IP"
echo "RHEL 9 OPS:  ${RHEL_IP:-pending}"
echo

failures=0
run() { check_flow "$@" || failures=$((failures+1)); }
case "$STAGE" in
  baseline)
    run "Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 ALLOW
    run "APP probe -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    run "Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 ALLOW
    run "Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 ALLOW
    ;;
  banp)
    run "Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 DENY
    run "APP probe -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    ;;
  app-np)
    run "Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 ALLOW
    run "APP probe -> WinAPP:8443" nsx-demo-app app=app-probe "$APP_IP" 8443 ALLOW
    ;;
  db-np)
    run "Jenkins -> WinDB:1435" nsx-demo-ops app=jenkins-probe "$DB_IP" 1435 ALLOW
    run "Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 DENY
    run "Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 ALLOW
    run "APP probe -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 DENY
    ;;
  final)
    run "APP probe -> WinDB:1435" nsx-demo-app app=app-probe "$DB_IP" 1435 ALLOW
    run "APP probe -> WinDB:61435" nsx-demo-app app=app-probe "$DB_IP" 61435 ALLOW
    run "APP probe -> WinDB:8080" nsx-demo-app app=app-probe "$DB_IP" 8080 DENY
    run "Rogue -> WinDB:1435" nsx-demo-rogue app=rogue-client "$DB_IP" 1435 DENY
    run "Jenkins -> WinDB:1435" nsx-demo-ops app=jenkins-probe "$DB_IP" 1435 ALLOW
    run "Jenkins -> WinDB:61435" nsx-demo-ops app=jenkins-probe "$DB_IP" 61435 DENY
    run "Corporate -> WinAPP:8443" nsx-demo-corp app=corporate-client "$APP_IP" 8443 ALLOW
    ;;
  *) echo "Usage: $0 {baseline|banp|app-np|db-np|final}" >&2; exit 2 ;;
esac

echo
(( failures == 0 )) && ok "All $STAGE expectations matched" || { fail "$failures expectation(s) did not match"; exit 1; }
