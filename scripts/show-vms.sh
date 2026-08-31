#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
printf '%-16s %-18s %-12s %-16s %s\n' NAMESPACE VM OS CUDN-IP STATUS
printf '%-16s %-18s %-12s %-16s %s\n' '----------------' '------------------' '------------' '----------------' '------'
for row in \
  "nsx-demo-app win2022-app Windows-2022" \
  "nsx-demo-db win2022-db Windows-2022" \
  "nsx-demo-ops rhel9-ops RHEL-9"; do
  read -r ns vm os <<<"$row"
  ip="$(vm_ip "$ns" "$vm")"
  ready="$(oc get vm "$vm" -n "$ns" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
  printf '%-16s %-18s %-12s %-16s %s\n' "$ns" "$vm" "$os" "${ip:-pending}" "${ready:-unknown}"
done
