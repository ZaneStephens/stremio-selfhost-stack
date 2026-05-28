[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Host,
    [string]$User = "ubuntu",
    [string]$RemoteDir = "/opt/stremio-stack",
    [string]$SshKey = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sshArgs = @()
if ($SshKey) { $sshArgs += @("-i", $SshKey) }
$target = "$User@$Host"

& ssh @sshArgs $target "cd '$RemoteDir' && docker compose ps && echo '--- logs last 40 ---' && docker compose logs --tail=40"
if ($LASTEXITCODE -ne 0) { throw "Remote docker compose check failed." }

if (Test-Path -LiteralPath "rendered/proxy-hosts.json") {
    $hosts = Get-Content -Raw -LiteralPath "rendered/proxy-hosts.json" | ConvertFrom-Json
    foreach ($entry in $hosts) {
        $url = "https://$($entry.domain)"
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 15 -ErrorAction Stop
            Write-Host "$url -> HTTP $($response.StatusCode)"
        } catch {
            Write-Warning "$url check failed: $($_.Exception.Message)"
        }
    }
}
