#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config
ensure_demo_password

render_one() {
  local ns="$1" secret="$2" computer="$3" ports="$4"
  local ps tmp xml encoded
  ps="$STATE_DIR/${secret}.ps1"
  xml="$STATE_DIR/${secret}-unattend.xml"

  cat > "$ps" <<POWERSHELL
\$ErrorActionPreference = 'Stop'
New-Item -Path 'C:\\NSXDemo' -ItemType Directory -Force | Out-Null
\$listener = @'
\$ports = @($ports)
\$jobs = @()
foreach (\$port in \$ports) {
  \$jobs += Start-Job -ArgumentList \$port -ScriptBlock {
    param(\$p)
    \$tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]\$p)
    \$tcp.Start()
    while (\$true) {
      \$client = \$tcp.AcceptTcpClient()
      try {
        \$stream = \$client.GetStream()
        \$bytes = [System.Text.Encoding]::UTF8.GetBytes("NSX policy demo listener on \$env:COMPUTERNAME port \$p`r`n")
        \$stream.Write(\$bytes, 0, \$bytes.Length)
      } finally { \$client.Close() }
    }
  }
}
Wait-Job -Job \$jobs | Out-Null
'@
Set-Content -Path 'C:\\NSXDemo\\listener.ps1' -Value \$listener -Encoding UTF8
New-NetFirewallRule -DisplayName 'NSX Demo TCP Listeners' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ports -ErrorAction SilentlyContinue | Out-Null
\$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\\NSXDemo\\listener.ps1'
\$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'NSXDemoListeners' -Action \$action -Trigger \$trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'NSXDemoListeners'
Set-Service -Name qemu-ga -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name qemu-ga -ErrorAction SilentlyContinue
POWERSHELL

  encoded="$(python3 - "$ps" <<'PY'
import base64, pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
print(base64.b64encode(s.encode('utf-16le')).decode())
PY
)"

  sed \
    -e "s|__COMPUTER_NAME__|$computer|g" \
    -e "s|__DEMO_PASSWORD__|$DEMO_ADMIN_PASSWORD|g" \
    -e "s|__POWERSHELL_ENCODED__|$encoded|g" \
    "$ROOT_DIR/manifests/vms/sysprep/unattend.xml.tpl" > "$xml"

  oc create secret generic "$secret" -n "$ns" --from-file=unattend.xml="$xml" --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "Rendered Windows sysprep secret: $ns/$secret"
}

render_one nsx-demo-app win2022-app-sysprep WIN2022-APP "8443"
render_one nsx-demo-db  win2022-db-sysprep  WIN2022-DB  "1435,61435,8080"
