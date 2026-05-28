[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("stremio-stack-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$configDir = Join-Path $tmp "config"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
$config = Join-Path $configDir "stack.env"
Copy-Item -LiteralPath "config/stack.env.example" -Destination $config

$content = Get-Content -LiteralPath $config
$content = $content -replace "^BASE_DOMAIN=.*", "BASE_DOMAIN=example.test"
$content = $content -replace "^AIOSTREAMS_HOST=.*", "AIOSTREAMS_HOST=aiostreams.example.test"
$content = $content -replace "^AIOMETADATA_HOST=.*", "AIOMETADATA_HOST=metadata.example.test"
$content = $content -replace "^NZBDAV_HOST=.*", "NZBDAV_HOST=nzbdav.example.test"
$content = $content -replace "^AIOSTREAMS_SECRET_KEY=.*", "AIOSTREAMS_SECRET_KEY=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$content = $content -replace "^AIOSTREAMS_AUTH_PASSWORD=.*", "AIOSTREAMS_AUTH_PASSWORD=test-password"
$content = $content -replace "^AIOMETADATA_ADMIN_KEY=.*", "AIOMETADATA_ADMIN_KEY=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
$content = $content -replace "^TMDB_API_KEY=.*", "TMDB_API_KEY=test-tmdb"
$content = $content -replace "^NZBDAV_ENABLED=.*", "NZBDAV_ENABLED=true"
$content = $content -replace "^VPN_MODE=.*", "VPN_MODE=hybrid"
$content = $content -replace "^GLUETUN_VPN_SERVICE_PROVIDER=.*", "GLUETUN_VPN_SERVICE_PROVIDER=mullvad"
$content = $content -replace "^GLUETUN_WIREGUARD_PRIVATE_KEY=.*", "GLUETUN_WIREGUARD_PRIVATE_KEY=test"
$content = $content -replace "^GLUETUN_WIREGUARD_ADDRESSES=.*", "GLUETUN_WIREGUARD_ADDRESSES=10.0.0.2/32"
$content | Set-Content -LiteralPath $config -Encoding utf8

$out = Join-Path $tmp "rendered"
& "$PSScriptRoot\render-stack.ps1" -ConfigPath $config -OutputDir $out | Out-Host

$compose = Get-Content -Raw -LiteralPath (Join-Path $out "docker-compose.yml")
$proxy = Get-Content -Raw -LiteralPath (Join-Path $out "proxy-hosts.json") | ConvertFrom-Json

if ($compose -notmatch "ghcr.io/viren070/aiostreams:latest") { throw "AIOStreams image missing" }
if ($compose -notmatch "ghcr.io/cedya77/aiometadata:latest") { throw "AIOMetadata image missing" }
if ($compose -notmatch "network_mode: service:gluetun") { throw "Hybrid NzbDav network mode missing" }
if (-not ($proxy | Where-Object { $_.domain -eq "nzbdav.example.test" -and $_.forward_host -eq "gluetun" })) { throw "NzbDav proxy host did not point at gluetun in hybrid mode" }
if (-not ($proxy | Where-Object { $_.domain -eq "aiostreams.example.test" })) { throw "AIOStreams proxy host missing" }

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Host "Render test passed."
