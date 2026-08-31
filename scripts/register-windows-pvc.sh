#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

SRC_NS="${1:-}"
PVC="${2:-}"
DS="${3:-$WINDOWS_DATASOURCE}"
[[ -n "$SRC_NS" && -n "$PVC" ]] || { echo "Usage: $0 <source-namespace> <generalized-windows-pvc> [datasource-name]" >&2; exit 2; }
oc get pvc "$PVC" -n "$SRC_NS" >/dev/null

cat <<YAML | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataSource
metadata:
  name: $DS
  namespace: $SRC_NS
  labels:
    demo.openshift.io/windows-version: "2022"
    demo.openshift.io/purpose: nsx-policy-demo
spec:
  source:
    pvc:
      name: $PVC
      namespace: $SRC_NS
YAML

ok "Created DataSource $SRC_NS/$DS"
echo "For this shell run:"
echo "  export WINDOWS_DATASOURCE_NS='$SRC_NS'"
echo "  export WINDOWS_DATASOURCE='$DS'"
