#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

info "Validating Bash syntax"
for f in "$ROOT_DIR"/scripts/*.sh; do
  bash -n "$f"
done
ok "All Bash scripts pass bash -n"

info "Checking final two-plane architecture"
for stale in \
  "$ROOT_DIR/manifests/policies/40-adminnetworkpolicy-db.yaml"; do
  if [[ -e "$stale" ]]; then
    fail "Stale file from an older build exists: $stale. Remove it before using this final demo."
    exit 1
  fi
done
for ns in nsx-admin-app nsx-admin-corp nsx-admin-ops nsx-admin-rogue; do
  grep -q "name: $ns" "$ROOT_DIR/manifests/base/03-admin-namespaces.yaml" || { fail "Missing $ns from admin namespace manifest"; exit 1; }
done
if grep -q 'k8s.ovn.org/primary-user-defined-network' "$ROOT_DIR/manifests/base/03-admin-namespaces.yaml"; then
  # The explanatory comment may contain the string; inspect parsed YAML below too.
  true
fi
grep -q 'name: admin-app-target' "$ROOT_DIR/manifests/base/04-admin-probes.yaml.tpl"
grep -q 'name: admin-corporate-client' "$ROOT_DIR/manifests/base/04-admin-probes.yaml.tpl"
grep -q 'name: admin-jenkins-client' "$ROOT_DIR/manifests/base/04-admin-probes.yaml.tpl"
grep -q 'name: admin-rogue-client' "$ROOT_DIR/manifests/base/04-admin-probes.yaml.tpl"
grep -q 'demo.openshift.io/policy-plane: admin' "$ROOT_DIR/manifests/policies/10-banp-app-guardrail.yaml"
grep -q 'demo.openshift.io/policy-plane: admin' "$ROOT_DIR/manifests/policies/40-adminnetworkpolicy-default-network.yaml"
grep -q 'nsx-admin-app' "$ROOT_DIR/scripts/test.sh"
grep -q 'nsx-demo-app' "$ROOT_DIR/scripts/test.sh"
if grep -R --exclude='validate-repo.sh' -nE 'APP_PROBE_DEFAULT_IP|APPprobe:8443 \[default\]|infrastructure-locked.*(ANP|BANP).*demo path' \
  "$ROOT_DIR/scripts" "$ROOT_DIR/README.md" "$ROOT_DIR/docs" 2>/dev/null; then
  fail "Stale infrastructure-locked admin-policy path reference found"
  exit 1
fi
ok "Dedicated default-network admin plane and Primary-CUDN workload plane are separated"

info "Validating unattend.xml template and FirstLogon command length"
python3 - "$ROOT_DIR/manifests/vms/sysprep/unattend.xml.tpl" <<'PY'
import sys, xml.etree.ElementTree as ET
p=sys.argv[1]
root=ET.parse(p).getroot()
ns={'u':'urn:schemas-microsoft-com:unattend'}
cmd=root.find('.//u:FirstLogonCommands/u:SynchronousCommand/u:CommandLine',ns)
assert cmd is not None and cmd.text
assert len(cmd.text) <= 1024, len(cmd.text)
print(f'FirstLogon CommandLine length: {len(cmd.text)}')
PY
ok "Unattend template is well-formed and command is <=1024 chars"

info "Validating Windows bootstrap template"
! grep -nE '\\$' "$ROOT_DIR/manifests/vms/sysprep/bootstrap.ps1.tpl" >/dev/null || {
  fail "bootstrap.ps1.tpl contains Linux-style line continuation"; exit 1;
}
grep -q '__PORTS__' "$ROOT_DIR/manifests/vms/sysprep/bootstrap.ps1.tpl"
ok "Bootstrap template contains expected port token and no Linux-style continuations"

info "Validating Windows VM boot bus and CUDN policy labels"
for f in "$ROOT_DIR/manifests/vms/11-win2022-app.yaml.tpl" "$ROOT_DIR/manifests/vms/12-win2022-db.yaml.tpl"; do
  grep -A2 'name: rootdisk' "$f" | grep -q 'bus: sata' || { fail "$f does not use SATA for rootdisk"; exit 1; }
  grep -q 'demo.openshift.io/component: vm' "$f" || { fail "$f is missing VM policy labels"; exit 1; }
done
grep -q 'demo.openshift.io/component: vm' "$ROOT_DIR/manifests/policies/20-networkpolicy-app.yaml"
grep -q 'demo.openshift.io/component: vm' "$ROOT_DIR/manifests/policies/30-networkpolicy-db.yaml"
ok "Windows templates use SATA and NetworkPolicy targets the real VM launcher labels"

info "Rendering sysprep files locally with safe test values"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -e 's|__COMPUTER_NAME__|WIN2022-TEST|g' -e 's|__WINDOWS_PASSWORD__|Demo-Test123!Aa9|g' \
  "$ROOT_DIR/manifests/vms/sysprep/unattend.xml.tpl" > "$tmp/unattend.xml"
sed 's|__PORTS__|8443|g' "$ROOT_DIR/manifests/vms/sysprep/bootstrap.ps1.tpl" > "$tmp/bootstrap.ps1"
python3 - "$tmp/unattend.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY
! grep -q '__[A-Z0-9_]*__' "$tmp/unattend.xml"
! grep -q '__PORTS__' "$tmp/bootstrap.ps1"
ok "Rendered sysprep files validate"

if python3 -c 'import yaml' >/dev/null 2>&1; then
  info "Parsing and validating YAML with PyYAML"
  python3 - "$ROOT_DIR" <<'PY'
import pathlib, sys, yaml
root=pathlib.Path(sys.argv[1])
repl={
  '__DEMO_IMAGE__':'quay.io/example/network-tools:latest',
  '__RHEL9_DATASOURCE__':'rhel9',
  '__RHEL9_DATASOURCE_NS__':'openshift-virtualization-os-images',
  '__WINDOWS_DATASOURCE__':'win2022-demo-v2',
  '__WINDOWS_DATASOURCE_NS__':'openshift-virtualization-os-images',
  '__WINDOWS_MEMORY__':'4Gi',
  '__WINDOWS_CORES__':'2',
  '__RHEL_MEMORY__':'2Gi',
  '__RHEL_CORES__':'2',
  '__DEMO_PASSWORD__':'Demo-Test123!Aa9',
}
paths=[]
for base in ('manifests','optional'):
    paths.extend((root/base).rglob('*.yaml'))
    paths.extend((root/base).rglob('*.yaml.tpl'))
for p in sorted(set(paths)):
    text=p.read_text()
    for a,b in repl.items(): text=text.replace(a,b)
    try:
        docs=list(yaml.safe_load_all(text))
    except Exception as e:
        raise SystemExit(f'YAML parse failed: {p}: {e}')
    if p.name == '03-admin-namespaces.yaml':
        for d in docs:
            labels=(d or {}).get('metadata',{}).get('labels',{})
            if 'k8s.ovn.org/primary-user-defined-network' in labels:
                raise SystemExit(f'Admin namespace incorrectly carries Primary UDN label: {d["metadata"]["name"]}')
            if labels.get('demo.openshift.io/policy-plane') != 'admin':
                raise SystemExit(f'Admin namespace missing policy-plane label: {d["metadata"]["name"]}')
print(f'Parsed {len(set(paths))} YAML files/templates')
PY
  ok "YAML files/templates parse and admin namespaces are default-network-only"
else
  warn "PyYAML not installed; skipping optional YAML parse"
fi

echo
ok "Repository validation complete"
