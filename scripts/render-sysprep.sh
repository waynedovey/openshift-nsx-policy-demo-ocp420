#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_oc
load_config

render_one() {
  local ns="$1" secret="$2" computer="$3" ports="$4"
  local ps xml encoded
  ps="$STATE_DIR/${secret}.ps1"
  xml="$STATE_DIR/${secret}-unattend.xml"

  # Keep this heredoc quoted. PowerShell uses backticks and $variables which
  # must not be interpreted by Bash. Only __PORTS__ is replaced afterwards.
  cat > "$ps" <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
$demoDir = 'C:\NSXDemo'
New-Item -Path $demoDir -ItemType Directory -Force | Out-Null

$listener = @'
$ErrorActionPreference = 'Stop'
$ports = @(__PORTS__)
$listeners = @()

foreach ($port in $ports) {
  $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]$port)
  $tcp.Start()
  $listeners += [pscustomobject]@{ Port = [int]$port; Listener = $tcp }
}

try {
  while ($true) {
    foreach ($entry in $listeners) {
      if ($entry.Listener.Pending()) {
        $client = $entry.Listener.AcceptTcpClient()
        try {
          $stream = $client.GetStream()
          $message = "NSX policy demo listener on $env:COMPUTERNAME port $($entry.Port)`r`n"
          $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
          $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
          $client.Close()
        }
      }
    }
    Start-Sleep -Milliseconds 100
  }
}
finally {
  foreach ($entry in $listeners) {
    try { $entry.Listener.Stop() } catch {}
  }
}
'@

Set-Content -Path "$demoDir\listener.ps1" -Value $listener -Encoding UTF8

# Open only the ports used by this VM. This keeps Windows Firewall from
# masking the OpenShift network-policy result.
$ports = @(__PORTS__)
Get-NetFirewallRule -DisplayName 'NSX Demo TCP Listeners' -ErrorAction SilentlyContinue |
  Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule \
  -DisplayName 'NSX Demo TCP Listeners' \
  -Direction Inbound \
  -Action Allow \
  -Protocol TCP \
  -LocalPort $ports | Out-Null

$action = New-ScheduledTaskAction \
  -Execute 'PowerShell.exe' \
  -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\NSXDemo\listener.ps1'
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask \
  -TaskName 'NSXDemoListeners' \
  -Action $action \
  -Trigger $trigger \
  -Settings $settings \
  -User 'SYSTEM' \
  -RunLevel Highest \
  -Force | Out-Null

Start-ScheduledTask -TaskName 'NSXDemoListeners'
Set-Service -Name qemu-ga -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name qemu-ga -ErrorAction SilentlyContinue

@(
  "ComputerName=$env:COMPUTERNAME"
  "Configured=$(Get-Date -Format o)"
  "Ports=$($ports -join ',')"
) | Set-Content -Path "$demoDir\configured.txt" -Encoding ASCII
POWERSHELL

  sed -i "s|__PORTS__|$ports|g" "$ps"

  encoded="$(python3 - "$ps" <<'PY'
import base64, pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
print(base64.b64encode(s.encode('utf-16le')).decode())
PY
)"

  sed \
    -e "s|__COMPUTER_NAME__|$computer|g" \
    -e "s|__POWERSHELL_ENCODED__|$encoded|g" \
    "$ROOT_DIR/manifests/vms/sysprep/unattend.xml.tpl" > "$xml"

  # Validate the rendered answer file before placing it in the Secret.
  python3 - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY

  oc create secret generic "$secret" -n "$ns" \
    --from-file=unattend.xml="$xml" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "Rendered Windows sysprep secret: $ns/$secret"
}

render_one nsx-demo-app win2022-app-sysprep WIN2022-APP "8443"
render_one nsx-demo-db  win2022-db-sysprep  WIN2022-DB  "1435,61435,8080"
