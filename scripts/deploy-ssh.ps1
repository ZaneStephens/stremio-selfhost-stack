[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Host,
    [string]$User = "ubuntu",
    [string]$RemoteDir = "/opt/stremio-stack",
    [string]$SshKey = "",
    [switch]$SkipRender
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $SkipRender) {
    & "$PSScriptRoot\render-stack.ps1"
}

$composePath = "rendered/docker-compose.yml"
if (-not (Test-Path -LiteralPath $composePath)) {
    throw "Missing $composePath. Run .\scripts\render-stack.ps1 first."
}

$sshTarget = "$User@$Host"
$sshArgs = @()
$scpArgs = @()
if ($SshKey) {
    $sshArgs += @("-i", $SshKey)
    $scpArgs += @("-i", $SshKey)
}

function Invoke-Remote {
    param([string]$Command)
    & ssh @sshArgs $sshTarget $Command
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed: $Command" }
}

Invoke-Remote "mkdir -p '$RemoteDir'"
& scp @scpArgs $composePath "$sshTarget`:$RemoteDir/docker-compose.yml"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }

$cfg = @{}
foreach ($line in Get-Content -LiteralPath "config/stack.env") {
    $trim = $line.Trim()
    if ($trim -eq "" -or $trim.StartsWith("#") -or -not $trim.Contains("=")) { continue }
    $idx = $trim.IndexOf("=")
    $cfg[$trim.Substring(0, $idx)] = $trim.Substring($idx + 1)
}

$proxyNetwork = if ($cfg.ContainsKey("PROXY_NETWORK")) { $cfg["PROXY_NETWORK"] } else { "proxy" }
$external = if ($cfg.ContainsKey("PROXY_NETWORK_EXTERNAL")) { $cfg["PROXY_NETWORK_EXTERNAL"].ToLowerInvariant() } else { "true" }
if (@("true", "1", "yes", "on").Contains($external)) {
    Invoke-Remote "docker network inspect '$proxyNetwork' >/dev/null 2>&1 || docker network create '$proxyNetwork'"
}

$npmContainer = if ($cfg.ContainsKey("NPM_CONTAINER_NAME")) { $cfg["NPM_CONTAINER_NAME"] } else { "" }
if ($npmContainer) {
    Invoke-Remote "if docker ps --format '{{.Names}}' | grep -qx '$npmContainer'; then docker network connect '$proxyNetwork' '$npmContainer' 2>/dev/null || true; fi"
}

Invoke-Remote "cd '$RemoteDir' && docker compose pull && docker compose up -d"
Write-Host "Deployed to $sshTarget`:$RemoteDir"
