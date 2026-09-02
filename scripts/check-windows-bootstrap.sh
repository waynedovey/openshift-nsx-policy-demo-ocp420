#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

for item in "nsx-demo-app win2022-app 8443" "nsx-demo-db win2022-db 1435,61435,8080"; do
  read -r ns vm ports <<<"$item"
  echo "=== $ns/$vm ==="
  oc get vm "$vm" -n "$ns" -o custom-columns='NAME:.metadata.name,READY:.status.ready,PRINTABLE:.status.printableStatus' || true
  echo -n "IP: "; vm_ip "$ns" "$vm" || true; echo
  echo -n "Sysprep Secret keys: "
  oc get secret "${vm}-sysprep" -n "$ns" -o go-template='{{range $k, $v := .data}}{{printf "%s " $k}}{{end}}' 2>/dev/null || true
  echo
  echo "Expected listener ports: $ports"
  echo
done

cat <<'TXT'
From each Windows console, run:
  Test-Path C:\NSXDemo\configured.txt
  Get-ChildItem C:\NSXDemo -ErrorAction SilentlyContinue
  Get-Content C:\NSXDemo\bootstrap.log -Tail 100 -ErrorAction SilentlyContinue
  Get-Content C:\NSXDemo\bootstrap-error.txt -ErrorAction SilentlyContinue
  Get-ScheduledTask -TaskName NSXDemoListeners -ErrorAction SilentlyContinue
  Get-ScheduledTaskInfo -TaskName NSXDemoListeners -ErrorAction SilentlyContinue
  Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 8443,1435,61435,8080

If C:\NSXDemo does not exist, inspect Windows setup logs:
  Get-Content C:\Windows\Panther\setuperr.log -Tail 100
  Get-Content C:\Windows\Panther\UnattendGC\setupact.log -Tail 150
TXT
