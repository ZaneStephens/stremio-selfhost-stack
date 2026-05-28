[CmdletBinding()]
param(
    [string]$ConfigPath = "config/stack.env",
    [string]$ExamplePath = "config/stack.env.example",
    [string]$BaseDomain = "",
    [string]$Email = "",
    [switch]$EnableNzbDav,
    [ValidateSet("off", "http-proxy", "hybrid")]
    [string]$VpnMode = "off",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-HexSecret {
    param([int]$Bytes = 32)
    $buffer = [byte[]]::new($Bytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function New-Password {
    param([int]$Bytes = 18)
    $buffer = [byte[]]::new($Bytes)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    return [Convert]::ToBase64String($buffer).TrimEnd("=").Replace("+", "x").Replace("/", "y")
}

if ((Test-Path -LiteralPath $ConfigPath) -and -not $Force) {
    throw "$ConfigPath already exists. Use -Force to replace it."
}
if (-not (Test-Path -LiteralPath $ExamplePath)) {
    throw "Example config not found: $ExamplePath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
$content = Get-Content -LiteralPath $ExamplePath

$replacements = @{
    "AIOSTREAMS_SECRET_KEY=" = "AIOSTREAMS_SECRET_KEY=$(New-HexSecret 32)"
    "AIOSTREAMS_AUTH_PASSWORD=" = "AIOSTREAMS_AUTH_PASSWORD=$(New-Password)"
    "AIOMETADATA_ADMIN_KEY=" = "AIOMETADATA_ADMIN_KEY=$(New-HexSecret 32)"
    "NZBDAV_ENABLED=false" = "NZBDAV_ENABLED=$(if ($EnableNzbDav) { 'true' } else { 'false' })"
    "VPN_MODE=off" = "VPN_MODE=$VpnMode"
}

if ($BaseDomain) {
    $replacements["BASE_DOMAIN=example.com"] = "BASE_DOMAIN=$BaseDomain"
    $replacements["AIOSTREAMS_HOST=aiostreams.example.com"] = "AIOSTREAMS_HOST=aiostreams.$BaseDomain"
    $replacements["AIOMETADATA_HOST=metadata.example.com"] = "AIOMETADATA_HOST=metadata.$BaseDomain"
    $replacements["NZBDAV_HOST=nzbdav.example.com"] = "NZBDAV_HOST=nzbdav.$BaseDomain"
}
if ($Email) {
    $replacements["LETSENCRYPT_EMAIL=you@example.com"] = "LETSENCRYPT_EMAIL=$Email"
}

$updated = foreach ($line in $content) {
    if ($replacements.ContainsKey($line)) { $replacements[$line] } else { $line }
}

$updated | Set-Content -LiteralPath $ConfigPath -Encoding utf8
Write-Host "Created $ConfigPath"
Write-Host "Edit it, then run: .\scripts\render-stack.ps1"
