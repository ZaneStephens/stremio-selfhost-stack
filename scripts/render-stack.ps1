[CmdletBinding()]
param(
    [string]$ConfigPath = "config/stack.env",
    [string]$OutputDir = "rendered"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path. Run .\scripts\new-config.ps1 first."
    }

    $data = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
        $idx = $trimmed.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $data[$key] = $value
    }
    return $data
}

function Get-Cfg {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$Default = ""
    )
    if ($Config.Contains($Key) -and $null -ne $Config[$Key] -and "$($Config[$Key])".Length -gt 0) {
        return "$($Config[$Key])"
    }
    return $Default
}

function Get-Bool {
    param([hashtable]$Config, [string]$Key, [bool]$Default = $false)
    $raw = (Get-Cfg $Config $Key ($(if ($Default) { "true" } else { "false" }))).ToLowerInvariant()
    return @("1", "true", "yes", "on", "enabled").Contains($raw)
}

function Quote-Yaml {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Add-EnvironmentBlock {
    param(
        [System.Text.StringBuilder]$Builder,
        [hashtable]$Environment,
        [int]$Indent = 6
    )
    $space = " " * $Indent
    [void]$Builder.AppendLine("$space" + "environment:")
    foreach ($key in ($Environment.Keys | Sort-Object)) {
        [void]$Builder.AppendLine("$space  $key`: $(Quote-Yaml "$($Environment[$key])")")
    }
}

function Add-Healthcheck {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Url,
        [int]$Indent = 6
    )
    $space = " " * $Indent
    [void]$Builder.AppendLine("$space" + "healthcheck:")
    [void]$Builder.AppendLine("$space  test: ['CMD-SHELL', 'wget --no-verbose --tries=1 --spider $Url || exit 1']")
    [void]$Builder.AppendLine("$space  interval: 30s")
    [void]$Builder.AppendLine("$space  timeout: 10s")
    [void]$Builder.AppendLine("$space  retries: 3")
    [void]$Builder.AppendLine("$space  start_period: 40s")
}

function Add-Networks {
    param(
        [System.Text.StringBuilder]$Builder,
        [string[]]$Networks,
        [int]$Indent = 6
    )
    if (-not $Networks -or $Networks.Count -eq 0) { return }
    $space = " " * $Indent
    [void]$Builder.AppendLine("$space" + "networks:")
    foreach ($network in $Networks) {
        [void]$Builder.AppendLine("$space  - $network")
    }
}

$cfg = Read-DotEnv $ConfigPath
$publicScheme = Get-Cfg $cfg "PUBLIC_SCHEME" "https"
$baseDomain = Get-Cfg $cfg "BASE_DOMAIN" "example.com"
$aiosHost = Get-Cfg $cfg "AIOSTREAMS_HOST" "aiostreams.$baseDomain"
$metaHost = Get-Cfg $cfg "AIOMETADATA_HOST" "metadata.$baseDomain"
$nzbdavHost = Get-Cfg $cfg "NZBDAV_HOST" "nzbdav.$baseDomain"
$aiosUrl = "${publicScheme}://$aiosHost"
$metaUrl = "${publicScheme}://$metaHost"
$nzbdavUrl = "${publicScheme}://$nzbdavHost"

$enableAios = Get-Bool $cfg "AIOSTREAMS_ENABLED" $true
$enableMeta = Get-Bool $cfg "AIOMETADATA_ENABLED" $true
$enableNzbDav = Get-Bool $cfg "NZBDAV_ENABLED" $false
$enableNpm = Get-Bool $cfg "ENABLE_NPM_SERVICE" $false
$vpnMode = (Get-Cfg $cfg "VPN_MODE" "off").ToLowerInvariant()
if (-not @("off", "http-proxy", "hybrid").Contains($vpnMode)) {
    throw "VPN_MODE must be off, http-proxy, or hybrid. Got: $vpnMode"
}
if ($vpnMode -eq "hybrid" -and -not $enableNzbDav) {
    throw "VPN_MODE=hybrid requires NZBDAV_ENABLED=true."
}
$enableGluetun = $vpnMode -ne "off"

$dataRoot = Get-Cfg $cfg "DATA_ROOT" "/opt/stremio-stack/data"
$tz = Get-Cfg $cfg "TZ" "Australia/Sydney"
$puid = Get-Cfg $cfg "PUID" "1000"
$pgid = Get-Cfg $cfg "PGID" "1000"
$proxyNetwork = Get-Cfg $cfg "PROXY_NETWORK" "proxy"
$internalNetwork = Get-Cfg $cfg "INTERNAL_NETWORK" "stremio_internal"
$proxyExternal = Get-Bool $cfg "PROXY_NETWORK_EXTERNAL" $true

$aiosPort = [int](Get-Cfg $cfg "AIOSTREAMS_INTERNAL_PORT" "3000")
$metaPort = [int](Get-Cfg $cfg "AIOMETADATA_INTERNAL_PORT" "3232")
$nzbdavPort = [int](Get-Cfg $cfg "NZBDAV_INTERNAL_PORT" "3000")
$gluetunProxyPort = [int](Get-Cfg $cfg "GLUETUN_HTTP_PROXY_PORT" "8888")

if ($enableAios -and -not (Get-Cfg $cfg "AIOSTREAMS_SECRET_KEY")) {
    throw "AIOSTREAMS_SECRET_KEY is required. Run .\scripts\new-config.ps1 or fill config/stack.env."
}
if ($enableAios -and -not (Get-Cfg $cfg "AIOSTREAMS_AUTH_PASSWORD")) {
    throw "AIOSTREAMS_AUTH_PASSWORD is required."
}
if ($enableMeta -and -not (Get-Cfg $cfg "AIOMETADATA_ADMIN_KEY")) {
    throw "AIOMETADATA_ADMIN_KEY is required."
}
if ($enableMeta -and -not (Get-Cfg $cfg "TMDB_API_KEY")) {
    Write-Warning "TMDB_API_KEY is blank. AIOMetadata may start but useful metadata features will not work until this is set."
}
if ($enableGluetun -and -not (Get-Cfg $cfg "GLUETUN_VPN_SERVICE_PROVIDER")) {
    Write-Warning "GLUETUN_VPN_SERVICE_PROVIDER is blank. The Gluetun container will not connect until VPN provider settings are filled."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$compose = [System.Text.StringBuilder]::new()
[void]$compose.AppendLine("name: stremio-stack")
[void]$compose.AppendLine("")
[void]$compose.AppendLine("services:")

if ($enableGluetun) {
    $gluetunEnv = [ordered]@{
        HTTPPROXY = "on"
        HTTPPROXY_LISTENING_ADDRESS = ":$gluetunProxyPort"
        FIREWALL_OUTBOUND_SUBNETS = Get-Cfg $cfg "GLUETUN_FIREWALL_OUTBOUND_SUBNETS" "172.16.0.0/12,192.168.0.0/16"
    }
    if ($vpnMode -eq "hybrid") {
        $gluetunEnv["FIREWALL_INPUT_PORTS"] = "$gluetunProxyPort,$nzbdavPort"
    } else {
        $gluetunEnv["FIREWALL_INPUT_PORTS"] = "$gluetunProxyPort"
    }
    foreach ($key in $cfg.Keys) {
        if ($key -like "GLUETUN_*" -and $key -notin @("GLUETUN_HTTP_PROXY_PORT", "GLUETUN_FIREWALL_OUTBOUND_SUBNETS")) {
            $realKey = $key.Substring("GLUETUN_".Length)
            $val = Get-Cfg $cfg $key
            if ($val.Length -gt 0) { $gluetunEnv[$realKey] = $val }
        }
    }
    [void]$compose.AppendLine("  gluetun:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'GLUETUN_IMAGE' 'qmcgaw/gluetun:latest')")
    [void]$compose.AppendLine("    container_name: gluetun")
    [void]$compose.AppendLine("    restart: unless-stopped")
    [void]$compose.AppendLine("    cap_add:")
    [void]$compose.AppendLine("      - NET_ADMIN")
    [void]$compose.AppendLine("    devices:")
    [void]$compose.AppendLine("      - /dev/net/tun:/dev/net/tun")
    Add-EnvironmentBlock $compose $gluetunEnv 4
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/gluetun:/gluetun")
    Add-Networks $compose @($internalNetwork, $proxyNetwork) 4
    [void]$compose.AppendLine("")
}

if ($enableAios) {
    $aiosEnv = [ordered]@{
        BASE_URL = $aiosUrl
        SECRET_KEY = Get-Cfg $cfg "AIOSTREAMS_SECRET_KEY"
        DATABASE_URI = "sqlite://./data/db.sqlite"
        PORT = "$aiosPort"
        NODE_ENV = "production"
        LOG_LEVEL = Get-Cfg $cfg "AIOSTREAMS_LOG_LEVEL" "info"
        LOG_FORMAT = "json"
        AIOSTREAMS_AUTH = "$(Get-Cfg $cfg 'AIOSTREAMS_AUTH_USER' 'admin'):$(Get-Cfg $cfg 'AIOSTREAMS_AUTH_PASSWORD')"
        AIOSTREAMS_AUTH_ADMINS = Get-Cfg $cfg "AIOSTREAMS_AUTH_USER" "admin"
        TEMPLATE_URLS = '["https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/Tamtaro-All-Templates-for-AIOStreams.json","https://raw.githubusercontent.com/Vidhin05/Releases-Regex/refs/heads/main/all-templates.json"]'
        TEMPLATE_REFRESH_INTERVAL = Get-Cfg $cfg "AIOSTREAMS_TEMPLATE_REFRESH_INTERVAL" "3600"
        WHITELISTED_SYNC_REFRESH_INTERVAL = Get-Cfg $cfg "AIOSTREAMS_SYNC_REFRESH_INTERVAL" "3600"
        SEL_SYNC_ACCESS = Get-Cfg $cfg "AIOSTREAMS_SEL_SYNC_ACCESS" "all"
        FEATURED_TEMPLATE_IDS = Get-Cfg $cfg "AIOSTREAMS_FEATURED_TEMPLATE_IDS" "tamtaro.complete,Vidhin05.english-template"
        WHITELISTED_REGEX_PATTERNS_URLS = '["https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/regexes.json","https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/German/regexes.json"]'
        WHITELISTED_SEL_URLS = '["https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ESEs-extended.json","https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ESEs-standard.json","https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-ISEs.json","https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/AIOStreams-SyncedURLs/Tamtaro-synced-PSEs.json","https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/expressions.json","https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/German/expressions.json","https://raw.githubusercontent.com/Vidhin05/Releases-Regex/main/English/legacy-expressions.json"]'
    }
    if ($enableGluetun) {
        $aiosEnv["ADDON_PROXY"] = "http://gluetun:$gluetunProxyPort"
        $aiosEnv["ADDON_PROXY_CONFIG"] = Get-Cfg $cfg "AIOSTREAMS_ADDON_PROXY_CONFIG" "*:true"
    }
    [void]$compose.AppendLine("  aiostreams:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'AIOSTREAMS_IMAGE' 'ghcr.io/viren070/aiostreams:latest')")
    [void]$compose.AppendLine("    container_name: aiostreams")
    [void]$compose.AppendLine("    restart: unless-stopped")
    Add-EnvironmentBlock $compose $aiosEnv 4
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/aiostreams:/app/data")
    $depends = @()
    if ($enableGluetun) { $depends += "gluetun" }
    if ($depends.Count -gt 0) {
        [void]$compose.AppendLine("    depends_on:")
        foreach ($dep in $depends) { [void]$compose.AppendLine("      - $dep") }
    }
    Add-Networks $compose @($internalNetwork, $proxyNetwork) 4
    [void]$compose.AppendLine("")
}

if ($enableMeta) {
    $metaEnv = [ordered]@{
        PORT = "$metaPort"
        HOST_NAME = $metaUrl
        NODE_ENV = "production"
        LOG_LEVEL = "info"
        DATABASE_URL = "sqlite:./data/aiometadata.db"
        REDIS_URL = "redis://aiometadata_redis:6379"
        ADMIN_KEY = Get-Cfg $cfg "AIOMETADATA_ADMIN_KEY"
        TMDB_API_KEY = Get-Cfg $cfg "TMDB_API_KEY"
        TVDB_API_KEY = Get-Cfg $cfg "TVDB_API_KEY"
        FANART_API_KEY = Get-Cfg $cfg "FANART_API_KEY"
        RPDB_API_KEY = Get-Cfg $cfg "RPDB_API_KEY"
        MDBLIST_API_KEY = Get-Cfg $cfg "MDBLIST_API_KEY"
        TRAKT_CLIENT_ID = Get-Cfg $cfg "TRAKT_CLIENT_ID"
        TRAKT_CLIENT_SECRET = Get-Cfg $cfg "TRAKT_CLIENT_SECRET"
        SIMKL_CLIENT_ID = Get-Cfg $cfg "SIMKL_CLIENT_ID"
        SIMKL_CLIENT_SECRET = Get-Cfg $cfg "SIMKL_CLIENT_SECRET"
        GEMINI_API_KEY = Get-Cfg $cfg "GEMINI_API_KEY"
        CACHE_WARMUP_MODE = Get-Cfg $cfg "AIOMETADATA_CACHE_WARMUP_MODE" "essential"
        CACHE_WARMUP_ON_STARTUP = "true"
        ENABLE_CACHE_WARMING = "true"
        TZ = $tz
    }
    if ($enableGluetun -and (Get-Bool $cfg "AIOMETADATA_ENABLE_PROXY" $true)) {
        $metaEnv["HTTP_PROXY"] = "http://gluetun:$gluetunProxyPort"
        $metaEnv["HTTPS_PROXY"] = "http://gluetun:$gluetunProxyPort"
        $metaEnv["NO_PROXY"] = "localhost,127.0.0.1,aiometadata_redis"
    }
    [void]$compose.AppendLine("  aiometadata:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'AIOMETADATA_IMAGE' 'ghcr.io/cedya77/aiometadata:latest')")
    [void]$compose.AppendLine("    container_name: aiometadata")
    [void]$compose.AppendLine("    restart: unless-stopped")
    Add-EnvironmentBlock $compose $metaEnv 4
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/aiometadata/data:/app/addon/data")
    [void]$compose.AppendLine("    depends_on:")
    [void]$compose.AppendLine("      aiometadata_redis:")
    [void]$compose.AppendLine("        condition: service_healthy")
    if ($enableGluetun) {
        [void]$compose.AppendLine("      gluetun:")
        [void]$compose.AppendLine("        condition: service_started")
    }
    Add-Healthcheck $compose "http://localhost:$metaPort/health" 4
    Add-Networks $compose @($internalNetwork, $proxyNetwork) 4
    [void]$compose.AppendLine("")

    [void]$compose.AppendLine("  aiometadata_redis:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'REDIS_IMAGE' 'redis:latest')")
    [void]$compose.AppendLine("    container_name: aiometadata_redis")
    [void]$compose.AppendLine("    restart: unless-stopped")
    [void]$compose.AppendLine("    command: redis-server --appendonly yes --save 3600 1")
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/aiometadata/cache:/data")
    [void]$compose.AppendLine("    healthcheck:")
    [void]$compose.AppendLine("      test: ['CMD', 'redis-cli', 'ping']")
    [void]$compose.AppendLine("      interval: 10s")
    [void]$compose.AppendLine("      timeout: 5s")
    [void]$compose.AppendLine("      retries: 5")
    Add-Networks $compose @($internalNetwork) 4
    [void]$compose.AppendLine("")
}

if ($enableNzbDav) {
    $nzbEnv = [ordered]@{
        PUID = $puid
        PGID = $pgid
        TZ = $tz
    }
    [void]$compose.AppendLine("  nzbdav:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'NZBDAV_IMAGE' 'nzbdav/nzbdav:latest')")
    [void]$compose.AppendLine("    container_name: nzbdav")
    [void]$compose.AppendLine("    restart: unless-stopped")
    if ($vpnMode -eq "hybrid") {
        [void]$compose.AppendLine("    network_mode: service:gluetun")
    } else {
        Add-Networks $compose @($internalNetwork, $proxyNetwork) 4
    }
    Add-EnvironmentBlock $compose $nzbEnv 4
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/nzbdav/config:/config")
    [void]$compose.AppendLine("      - /mnt:/mnt")
    [void]$compose.AppendLine("    healthcheck:")
    [void]$compose.AppendLine("      test: ['CMD-SHELL', 'curl -f http://localhost:$nzbdavPort/health || exit 1']")
    [void]$compose.AppendLine("      interval: 1m")
    [void]$compose.AppendLine("      retries: 3")
    [void]$compose.AppendLine("      start_period: 5s")
    [void]$compose.AppendLine("      timeout: 5s")
    if ($enableGluetun) {
        [void]$compose.AppendLine("    depends_on:")
        [void]$compose.AppendLine("      - gluetun")
    }
    [void]$compose.AppendLine("")
}

if ($enableNpm) {
    [void]$compose.AppendLine("  nginx-proxy-manager:")
    [void]$compose.AppendLine("    image: $(Get-Cfg $cfg 'NPM_IMAGE' 'jc21/nginx-proxy-manager:latest')")
    [void]$compose.AppendLine("    container_name: $(Get-Cfg $cfg 'NPM_CONTAINER_NAME' 'nginx-proxy-manager')")
    [void]$compose.AppendLine("    restart: unless-stopped")
    [void]$compose.AppendLine("    ports:")
    [void]$compose.AppendLine("      - '$(Get-Cfg $cfg 'NPM_HTTP_PORT' '80'):80'")
    [void]$compose.AppendLine("      - '$(Get-Cfg $cfg 'NPM_HTTPS_PORT' '443'):443'")
    [void]$compose.AppendLine("      - '$(Get-Cfg $cfg 'NPM_ADMIN_PORT' '81'):81'")
    [void]$compose.AppendLine("    environment:")
    [void]$compose.AppendLine("      TZ: $(Quote-Yaml $tz)")
    [void]$compose.AppendLine("    volumes:")
    [void]$compose.AppendLine("      - $dataRoot/npm/data:/data")
    [void]$compose.AppendLine("      - $dataRoot/npm/letsencrypt:/etc/letsencrypt")
    Add-Networks $compose @($proxyNetwork) 4
    [void]$compose.AppendLine("")
}

[void]$compose.AppendLine("networks:")
[void]$compose.AppendLine("  ${internalNetwork}:")
[void]$compose.AppendLine("    name: $internalNetwork")
[void]$compose.AppendLine("  ${proxyNetwork}:")
[void]$compose.AppendLine("    name: $proxyNetwork")
if ($proxyExternal) {
    [void]$compose.AppendLine("    external: true")
}

$composePath = Join-Path $OutputDir "docker-compose.yml"
$compose.ToString() | Set-Content -LiteralPath $composePath -Encoding utf8

$proxyHosts = @()
if ($enableAios) {
    $proxyHosts += [ordered]@{
        name = "AIOStreams"
        domain = $aiosHost
        forward_scheme = "http"
        forward_host = "aiostreams"
        forward_port = $aiosPort
        websocket = $true
    }
}
if ($enableMeta) {
    $proxyHosts += [ordered]@{
        name = "AIOMetadata"
        domain = $metaHost
        forward_scheme = "http"
        forward_host = "aiometadata"
        forward_port = $metaPort
        websocket = $true
    }
}
if ($enableNzbDav) {
    $forwardHost = if ($vpnMode -eq "hybrid") { "gluetun" } else { "nzbdav" }
    $proxyHosts += [ordered]@{
        name = "NzbDav"
        domain = $nzbdavHost
        forward_scheme = "http"
        forward_host = $forwardHost
        forward_port = $nzbdavPort
        websocket = $true
    }
}
$proxyPath = Join-Path $OutputDir "proxy-hosts.json"
$proxyHosts | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $proxyPath -Encoding utf8

$next = @"
# Next Steps

Rendered at: $(Get-Date -Format o)

Compose: $composePath
Proxy hosts: $proxyPath

Public URLs:
- AIOStreams: $aiosUrl/stremio/configure
- AIOMetadata: $metaUrl/configure
$(if ($enableNzbDav) { "- NzbDav: $nzbdavUrl" } else { "" })

AIOStreams template deep link:
$aiosUrl/stremio/configure?template=https://raw.githubusercontent.com/Tam-Taro/SEL-Filtering-and-Sorting/refs/heads/main/Tamtaro-All-Templates-for-AIOStreams.json&templateId=tamtaro.complete

If using NPM automation:
.\scripts\configure-npm.ps1

If deploying over SSH:
.\scripts\deploy-ssh.ps1 -Host <server> -User <ssh-user>
"@
$next | Set-Content -LiteralPath (Join-Path $OutputDir "next-steps.md") -Encoding utf8

Write-Host "Rendered $composePath"
Write-Host "Rendered $proxyPath"
Write-Host "Rendered $(Join-Path $OutputDir 'next-steps.md')"
