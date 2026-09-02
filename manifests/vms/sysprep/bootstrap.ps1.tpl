$ErrorActionPreference = 'Stop'

$DemoDir = 'C:\NSXDemo'
$BootstrapLog = Join-Path $DemoDir 'bootstrap.log'
$BootstrapError = Join-Path $DemoDir 'bootstrap-error.txt'
$Ports = @(__PORTS__)

New-Item -Path $DemoDir -ItemType Directory -Force | Out-Null

try {
    Start-Transcript -Path $BootstrapLog -Append -Force | Out-Null

    $ListenerScript = @'
$ErrorActionPreference = 'Stop'
$ports = @(__PORTS__)
$listeners = @()

foreach ($port in $ports) {
    $tcp = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        [int]$port
    )
    $tcp.Start()
    $listeners += [pscustomobject]@{
        Port = [int]$port
        Listener = $tcp
    }
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

    Set-Content -Path (Join-Path $DemoDir 'listener.ps1') -Value $ListenerScript -Encoding UTF8

    Get-NetFirewallRule -DisplayName 'NSX Demo TCP Listeners' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    $FirewallParams = @{
        DisplayName = 'NSX Demo TCP Listeners'
        Direction   = 'Inbound'
        Action      = 'Allow'
        Protocol    = 'TCP'
        LocalPort   = $Ports
    }
    New-NetFirewallRule @FirewallParams | Out-Null

    $TaskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\NSXDemo\listener.ps1'
    $TaskTrigger = New-ScheduledTaskTrigger -AtStartup
    $TaskSettings = New-ScheduledTaskSettingsSet -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName 'NSXDemoListeners' -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Start-ScheduledTask -TaskName 'NSXDemoListeners'

    Set-Service -Name qemu-ga -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name qemu-ga -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    @(
        "ComputerName=$env:COMPUTERNAME"
        "Configured=$(Get-Date -Format o)"
        "Ports=$($Ports -join ',')"
    ) | Set-Content -Path (Join-Path $DemoDir 'configured.txt') -Encoding ASCII
}
catch {
    $_ | Out-String | Set-Content -Path $BootstrapError -Encoding UTF8
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
