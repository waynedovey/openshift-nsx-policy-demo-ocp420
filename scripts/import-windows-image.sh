#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

IMAGE="${1:-}"
[[ -n "$IMAGE" ]] || { echo "Usage: $0 /path/to/generalized-win2022.qcow2" >&2; exit 2; }
[[ -f "$IMAGE" ]] || { fail "File not found: $IMAGE"; exit 1; }
command -v virtctl >/dev/null 2>&1 || { fail "virtctl is required for image upload"; exit 1; }

SIZE="${WINDOWS_IMAGE_SIZE:-70Gi}"
SC="${WINDOWS_STORAGE_CLASS:-ocs-external-storagecluster-ceph-rbd}"

if oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null 2>&1; then
  fail "DataSource $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE already exists. Refusing to overwrite it."
  exit 1
fi

info "Uploading generalized Windows Server 2022 image"
echo "Namespace:     $WINDOWS_DATASOURCE_NS"
echo "DataSource:    $WINDOWS_DATASOURCE"
echo "StorageClass:  $SC"
echo "Size:          $SIZE"

args=(
  image-upload dv "$WINDOWS_DATASOURCE"
  --namespace="$WINDOWS_DATASOURCE_NS"
  --datasource
  --size="$SIZE"
  --image-path="$IMAGE"
  --storage-class="$SC"
  --access-mode=ReadWriteOnce
  --wait-secs=600
)
if virtctl image-upload --help 2>&1 | grep -q -- '--volume-mode'; then
  args+=(--volume-mode=block)
fi
virtctl "${args[@]}" ${VIRTCTL_UPLOAD_EXTRA_ARGS:-}

oc label datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" \
  demo.openshift.io/windows-version=2022 \
  demo.openshift.io/purpose=nsx-policy-demo --overwrite >/dev/null

oc get datasource "$WINDOWS_DATASOURCE" -n "$WINDOWS_DATASOURCE_NS" >/dev/null
ok "Windows boot source ready: $WINDOWS_DATASOURCE_NS/$WINDOWS_DATASOURCE"
