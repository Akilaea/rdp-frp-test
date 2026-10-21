[CmdletBinding()]
param(
    [string]$StatePath = "",
    [int]$Retries = 8,
    [int]$RetryDelaySeconds = 3,
    [int]$TimeoutMs = 5000,
    [switch]$TcpOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "FrpHelpers.ps1")

if (-not $StatePath) {
    if ($env:RDP_STATE_PATH) {
        $StatePath = $env:RDP_STATE_PATH
    } else {
        $StatePath = "$env:ProgramData\rdp-frp\state.json"
    }
}

$state = Read-StateFile -Path $StatePath
$userName = $state.userName
$password = $state.password
if (-not $userName -and $env:RDP_USER) { $userName = $env:RDP_USER }
if (-not $password -and $env:RDP_PASSWORD) { $password = $env:RDP_PASSWORD }
if (-not $userName) { $userName = "RDP" }

$frpcProcess = $null
if ($state.pid) {
    $frpcProcess = Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue
    if ($frpcProcess -and $frpcProcess.ProcessName -ne "frpc") { $frpcProcess = $null }
}
if (-not $frpcProcess) {
    throw "frpc is not running (state PID $($state.pid)). Start the tunnel again."
}

Write-Host "[*] Testing TCP connectivity to $($state.serverAddr):$($state.remotePort) ..."
$tcpOk = Wait-TcpPort `
    -ComputerName $state.serverAddr `
    -Port ([int]$state.remotePort) `
    -Retries $Retries `
    -RetryDelaySeconds $RetryDelaySeconds `
    -TimeoutMs $TimeoutMs

if (-not $tcpOk) {
    throw "TCP connection to $($state.serverAddr):$($state.remotePort) failed. Check frps allowPorts, the cloud security group, and your outbound firewall."
}
Write-Host "[+] TCP connectivity successful."

if (-not $TcpOnly) {
    Write-Host "[*] Performing an end-to-end RDP handshake ..."
    $rdpOk = Wait-RdpHandshake `
        -ComputerName $state.serverAddr `
        -Port ([int]$state.remotePort) `
        -Retries 4 `
        -RetryDelaySeconds 2 `
        -TimeoutMs $TimeoutMs
    if (-not $rdpOk) {
        throw "The remote port is reachable, but RDP did not answer. Ensure RDP is enabled (scripts\Enable-Rdp.ps1) and TermService is running."
    }
    Write-Host "[+] RDP handshake successful."
}

Write-AccessBanner `
    -ServerAddr $state.serverAddr `
    -RemotePort ([int]$state.remotePort) `
    -UserName $userName `
    -Password $password
