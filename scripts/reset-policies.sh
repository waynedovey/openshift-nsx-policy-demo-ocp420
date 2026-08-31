#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc

info "Removing demo policy objects only"
oc delete anp nsx-demo-db-security --ignore-not-found >/dev/null
oc delete networkpolicy app-ingress -n nsx-demo-app --ignore-not-found >/dev/null
oc delete networkpolicy db-ingress -n nsx-demo-db --ignore-not-found >/dev/null

if oc get banp default >/dev/null 2>&1; then
  if banp_owned_by_demo; then
    oc delete banp default --ignore-not-found >/dev/null
  else
    warn "Leaving existing non-demo BANP/default untouched"
  fi
fi
ok "Demo policies reset"
