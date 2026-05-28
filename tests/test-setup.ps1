[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$setupScript = Join-Path $repoRoot "scripts/setup.ps1"
if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "Missing setup script: $setupScript"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("stremio-setup-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $answersPath = Join-Path $tmp "answers.json"
    $configPath = Join-Path $tmp "config/stack.env"
    $renderDir = Join-Path $tmp "rendered"

    @{
        readPrerequisites = $true
        publicScheme = "https"
        baseDomain = "example.test"
        letsEncryptEmail = "admin@example.test"
        aiostreamsHost = "aio.example.test"
        aiometadataHost = "meta.example.test"
        nzbdavHost = "nzb.example.test"
        aiostreamsAuthUser = "owner"
        aiostreamsAuthPassword = "owner-test-password"
        tmdbApiKey = "tmdb-test-key"
        tvdbApiKey = "tvdb-test-key"
        fanartApiKey = ""
        rpdbApiKey = ""
        mdblistApiKey = ""
        traktClientId = ""
        traktClientSecret = ""
        simklClientId = ""
        simklClientSecret = ""
        geminiApiKey = ""
        enableNzbDav = $true
        nzbdavEnableRclone = $false
        vpnMode = "http-proxy"
        gluetunVpnServiceProvider = "mullvad"
        gluetunVpnType = "wireguard"
        gluetunWireguardPrivateKey = "test-private-key"
        gluetunWireguardAddresses = "10.64.0.2/32"
        enableNpmService = $false
        npmContainerName = "nginx-proxy-manager"
        npmBaseUrl = "http://127.0.0.1:81"
        npmIdentity = "admin@example.test"
        npmSecret = "npm-test-password"
        npmCreateProxyHosts = $false
        deploymentMode = "render"
        confirmRender = $true
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $answersPath -Encoding utf8

    & $setupScript -NonInteractive -AnswersPath $answersPath -ConfigPath $configPath -RenderOutputDir $renderDir -Force -SkipDeploy -SkipNpm

    $config = Get-Content -Raw -LiteralPath $configPath
    if ($config -notmatch "BASE_DOMAIN=example\.test") { throw "BASE_DOMAIN was not written" }
    if ($config -notmatch "AIOSTREAMS_HOST=aio\.example\.test") { throw "AIOSTREAMS_HOST was not written" }
    if ($config -notmatch "AIOSTREAMS_AUTH_USER=owner") { throw "AIOSTREAMS_AUTH_USER was not written" }
    if ($config -notmatch "AIOSTREAMS_AUTH_PASSWORD=owner-test-password") { throw "AIOSTREAMS_AUTH_PASSWORD was not written" }
    if ($config -notmatch "TMDB_API_KEY=tmdb-test-key") { throw "TMDB_API_KEY was not written" }
    if ($config -notmatch "NZBDAV_ENABLED=true") { throw "NZBDAV_ENABLED was not written" }
    if ($config -notmatch "VPN_MODE=http-proxy") { throw "VPN_MODE was not written" }
    if ($config -notmatch "ENABLE_NPM_SERVICE=false") { throw "ENABLE_NPM_SERVICE was not written" }
    if ($config -notmatch "AIOSTREAMS_SECRET_KEY=[0-9a-f]{64}") { throw "AIOSTREAMS_SECRET_KEY was not generated" }
    if ($config -notmatch "AIOMETADATA_ADMIN_KEY=[0-9a-f]{64}") { throw "AIOMETADATA_ADMIN_KEY was not generated" }

    $composePath = Join-Path $renderDir "docker-compose.yml"
    $proxyPath = Join-Path $renderDir "proxy-hosts.json"
    $summaryPath = Join-Path $renderDir "setup-summary.md"
    if (-not (Test-Path -LiteralPath $composePath)) { throw "docker-compose.yml was not rendered" }
    if (-not (Test-Path -LiteralPath $proxyPath)) { throw "proxy-hosts.json was not rendered" }
    if (-not (Test-Path -LiteralPath $summaryPath)) { throw "setup-summary.md was not written" }

    $summary = Get-Content -Raw -LiteralPath $summaryPath
    if ($summary -match "owner-test-password") { throw "setup summary leaked AIOStreams password" }
    if ($summary -match "tmdb-test-key") { throw "setup summary leaked TMDB key" }
    if ($summary -notmatch "https://aio\.example\.test/stremio/configure") { throw "setup summary missing AIOStreams URL" }

    Write-Host "Setup test passed."
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
