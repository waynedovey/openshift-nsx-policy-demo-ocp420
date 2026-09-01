#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

for item in "nsx-demo-app win2022-app 8443" "nsx-demo-db win2022-db 1435"; do
  read -r ns vm port <<<"$item"
  echo "=== $ns/$vm ==="
  oc get vm "$vm" -n "$ns" -o custom-columns='NAME:.metadata.name,READY:.status.ready,PRINTABLE:.status.printableStatus' || true
  echo -n "IP: "
  vm_ip "$ns" "$vm" || true
  echo
  echo "Sysprep secret key:"
  oc get secret "${vm}-sysprep" -n "$ns" -o jsonpath='{.data.unattend\.xml}' >/dev/null 2>&1 \
    && echo "  PASS unattend.xml present" \
    || echo "  FAIL unattend.xml missing"
  echo "Expected listener port: $port"
  echo
 done

echo "From the Windows console run:"
echo "  Test-Path C:\\NSXDemo\\configured.txt"
echo "  Get-Content C:\\NSXDemo\\configured.txt"
echo "  Get-ScheduledTask -TaskName NSXDemoListeners"
echo "  Get-ScheduledTaskInfo -TaskName NSXDemoListeners"
echo "  Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 8443,1435,61435,8080"
echo "  Get-Content C:\\Windows\\Panther\\UnattendGC\\setupact.log -Tail 100"
