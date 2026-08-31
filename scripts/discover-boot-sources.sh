#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

info "Boot sources / DataSources visible to the demo"
oc get datasource -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,SOURCE_KIND:.spec.source.pvc.name,SNAPSHOT:.spec.source.snapshot.name' 2>/dev/null || true

echo
if oc get datasource "$RHEL9_DATASOURCE" -n "$RHEL9_DATASOURCE_NS" >/dev/null 2>&1; then
  ok "RHEL 9 DataSource found: $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"
else
  warn "RHEL 9 DataSource not found: $RHEL9_DATASOURCE_NS/$RHEL9_DATASOURCE"
fi

if oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null 2>&1; then
  ok "Windows 2022 DataSource found: $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"
else
  warn "Windows 2022 DataSource not found: $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"
  echo "Use: ./scripts/import-windows-image.sh /path/to/generalized-win2022.qcow2"
fi
