#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
APP_IP="$(vm_ip nsx-demo-app win2022-app)"
DB_IP="$(vm_ip nsx-demo-db win2022-db)"
RHEL_IP="$(vm_ip nsx-demo-ops rhel9-ops)"
cat <<EOF2
VM guest IPs
  win2022-app : $APP_IP
  win2022-db  : $DB_IP
  rhel9-ops   : $RHEL_IP

For a true VM-to-VM check, open the guest console from OpenShift Virtualization.

From win2022-app PowerShell:
  Test-NetConnection $DB_IP -Port 1435
  Test-NetConnection $DB_IP -Port 61435
  Test-NetConnection $DB_IP -Port 8080

From win2022-db PowerShell:
  Test-NetConnection $APP_IP -Port 8443

From rhel9-ops console:
  timeout 3 bash -c '</dev/tcp/$DB_IP/1435' && echo ALLOW || echo DENY
  timeout 3 bash -c '</dev/tcp/$DB_IP/61435' && echo ALLOW || echo DENY

Note: primary UDN/CUDN VMs do not support virtctl ssh or oc port-forward. Use the web/VNC/serial console for guest-side tests.
EOF2
