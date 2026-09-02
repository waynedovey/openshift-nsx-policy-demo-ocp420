#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "Removing only the two Windows demo clones and their specialization state"
for item in "nsx-demo-app win2022-app" "nsx-demo-db win2022-db"; do
  read -r ns vm <<<"$item"
  oc delete vm "$vm" -n "$ns" --ignore-not-found --wait=true --timeout=180s >/dev/null || true
  oc delete dv "${vm}-root" -n "$ns" --ignore-not-found --wait=true --timeout=180s >/dev/null || true
  oc delete secret "${vm}-sysprep" -n "$ns" --ignore-not-found >/dev/null || true
  for _ in $(seq 1 60); do
    oc get vmi "$vm" -n "$ns" >/dev/null 2>&1 || break
    sleep 2
  done
done
ok "Windows clones removed; CUDN, RHEL VM and reusable boot sources were left intact"

exec "$ROOT_DIR/scripts/setup.sh"
