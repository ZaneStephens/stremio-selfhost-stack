[CmdletBinding()]
param(
    [string]$ConfigPath = "config/stack.env",
    [string]$ProxyHostsPath = "rendered/proxy-hosts.json",
    [string]$NpmUrl = "",
    [string]$Identity = "",
    [string]$Secret = "",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-DotEnv {
    param([string]$Path)
    $data = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim -eq "" -or $trim.StartsWith("#") -or -not $trim.Contains("=")) { continue }
        $idx = $trim.IndexOf("=")
        $data[$trim.Substring(0, $idx)] = $trim.Substring($idx + 1)
    }
    return $data
}

if (-not (Test-Path -LiteralPath $ProxyHostsPath)) {
    throw "Missing $ProxyHostsPath. Run .\scripts\render-stack.ps1 first."
}
$cfg = Read-DotEnv $ConfigPath
if (-not $NpmUrl) { $NpmUrl = if ($cfg.ContainsKey("NPM_BASE_URL")) { $cfg["NPM_BASE_URL"] } else { "http://127.0.0.1:81" } }
if (-not $Identity) { $Identity = if ($cfg.ContainsKey("NPM_IDENTITY")) { $cfg["NPM_IDENTITY"] } else { "" } }
if (-not $Secret) { $Secret = if ($cfg.ContainsKey("NPM_SECRET")) { $cfg["NPM_SECRET"] } else { "" } }
if (-not $Identity -or -not $Secret) { throw "NPM credentials are required. Set NPM_IDENTITY and NPM_SECRET or pass -Identity/-Secret." }

$requestLetsEncrypt = if ($cfg.ContainsKey("NPM_REQUEST_LETSENCRYPT")) { @("true","1","yes","on").Contains($cfg["NPM_REQUEST_LETSENCRYPT"].ToLowerInvariant()) } else { $true }
$sslForced = if ($cfg.ContainsKey("NPM_SSL_FORCED")) { @("true","1","yes","on").Contains($cfg["NPM_SSL_FORCED"].ToLowerInvariant()) } else { $true }
$http2 = if ($cfg.ContainsKey("NPM_HTTP2_SUPPORT")) { @("true","1","yes","on").Contains($cfg["NPM_HTTP2_SUPPORT"].ToLowerInvariant()) } else { $true }
$blockExploits = if ($cfg.ContainsKey("NPM_BLOCK_EXPLOITS")) { @("true","1","yes","on").Contains($cfg["NPM_BLOCK_EXPLOITS"].ToLowerInvariant()) } else { $true }
$websocket = if ($cfg.ContainsKey("NPM_ALLOW_WEBSOCKET")) { @("true","1","yes","on").Contains($cfg["NPM_ALLOW_WEBSOCKET"].ToLowerInvariant()) } else { $true }

$proxyHosts = Get-Content -Raw -LiteralPath $ProxyHostsPath | ConvertFrom-Json
Write-Host "NPM URL: $NpmUrl"
if ($DryRun) {
    $proxyHosts | Format-Table name, domain, forward_host, forward_port
    Write-Host "Dry run only."
    return
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "$NpmUrl/api/tokens" -ContentType "application/json" -Body (@{
    identity = $Identity
    secret = $Secret
} | ConvertTo-Json)

if (-not $tokenResponse.token) { throw "NPM did not return an access token." }
$headers = @{ Authorization = "Bearer $($tokenResponse.token)" }
$existing = Invoke-RestMethod -Method Get -Uri "$NpmUrl/api/nginx/proxy-hosts" -Headers $headers

foreach ($hostEntry in $proxyHosts) {
    $domain = "$($hostEntry.domain)"
    $found = $existing | Where-Object { $_.domain_names -contains $domain } | Select-Object -First 1
    if ($found) {
        Write-Host "Skipping existing proxy host: $domain"
        continue
    }

    $payload = [ordered]@{
        domain_names = @($domain)
        forward_scheme = "$($hostEntry.forward_scheme)"
        forward_host = "$($hostEntry.forward_host)"
        forward_port = [int]$hostEntry.forward_port
        access_list_id = 0
        certificate_id = $(if ($requestLetsEncrypt) { "new" } else { 0 })
        ssl_forced = $sslForced
        hsts_enabled = $false
        hsts_subdomains = $false
        http2_support = $http2
        block_exploits = $blockExploits
        caching_enabled = $false
        allow_websocket_upgrade = $websocket
        advanced_config = ""
        enabled = $true
        meta = @{ dns_challenge = $false }
        locations = @()
    }

    Write-Host "Creating proxy host: $domain -> $($hostEntry.forward_host):$($hostEntry.forward_port)"
    Invoke-RestMethod -Method Post -Uri "$NpmUrl/api/nginx/proxy-hosts" -Headers $headers -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 10) | Out-Null
}

Write-Host "NPM proxy host configuration complete."
