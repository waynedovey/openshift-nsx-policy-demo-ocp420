#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config
ensure_demo_password

render_one() {
  local ns="$1" secret="$2" computer="$3" ports="$4"
  local bootstrap xml
  bootstrap="$STATE_DIR/${secret}-bootstrap.ps1"
  xml="$STATE_DIR/${secret}-unattend.xml"

  sed "s|__PORTS__|$ports|g" \
    "$ROOT_DIR/manifests/vms/sysprep/bootstrap.ps1.tpl" > "$bootstrap"

  sed \
    -e "s|__COMPUTER_NAME__|$computer|g" \
    -e "s|__WINDOWS_PASSWORD__|$DEMO_ADMIN_PASSWORD|g" \
    "$ROOT_DIR/manifests/vms/sysprep/unattend.xml.tpl" > "$xml"

  python3 - "$xml" "$bootstrap" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

xml_path = pathlib.Path(sys.argv[1])
ps_path = pathlib.Path(sys.argv[2])
root = ET.parse(xml_path).getroot()
ns = {"u": "urn:schemas-microsoft-com:unattend"}
cmd = root.find(".//u:FirstLogonCommands/u:SynchronousCommand/u:CommandLine", ns)
if cmd is None or not (cmd.text or "").strip():
    raise SystemExit("FirstLogonCommands/CommandLine missing")
if len(cmd.text) > 1024:
    raise SystemExit(f"FirstLogon CommandLine too long: {len(cmd.text)}")
text = ps_path.read_text()
if "__PORTS__" in text:
    raise SystemExit("bootstrap.ps1 still contains __PORTS__")
if "\\\n" in text:
    raise SystemExit("bootstrap.ps1 contains Linux-style backslash line continuation")
print(f"Validated {xml_path.name}: FirstLogon CommandLine={len(cmd.text)} chars")
PY

  oc create secret generic "$secret" -n "$ns" \
    --from-file=unattend.xml="$xml" \
    --from-file=bootstrap.ps1="$bootstrap" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null

  [[ -n "$(oc get secret "$secret" -n "$ns" -o jsonpath='{.data.unattend\.xml}' 2>/dev/null || true)" ]] || {
    fail "Sysprep Secret $ns/$secret is missing unattend.xml"
    exit 1
  }
  [[ -n "$(oc get secret "$secret" -n "$ns" -o jsonpath='{.data.bootstrap\.ps1}' 2>/dev/null || true)" ]] || {
    fail "Sysprep Secret $ns/$secret is missing bootstrap.ps1"
    exit 1
  }

  ok "Rendered Windows sysprep media: $ns/$secret (unattend.xml + bootstrap.ps1)"
}

render_one nsx-demo-app win2022-app-sysprep WIN2022-APP "8443"
render_one nsx-demo-db  win2022-db-sysprep  WIN2022-DB  "1435,61435,8080"
