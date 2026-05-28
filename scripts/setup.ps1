[CmdletBinding()]
param(
    [string]$ConfigPath = "config/stack.env",
    [string]$ExamplePath = "config/stack.env.example",
    [string]$RenderOutputDir = "rendered",
    [switch]$NonInteractive,
    [string]$AnswersPath = "",
    [switch]$Force,
    [switch]$Resume,
    [switch]$SkipRender,
    [switch]$SkipDeploy,
    [switch]$SkipNpm,
    [switch]$NoEdit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Answers = $null

function New-HexSecret {
    param([int]$Bytes = 32)
    $buffer = [byte[]]::new($Bytes)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buffer)
    $rng.Dispose()
    return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function New-Password {
    param([int]$Bytes = 18)
    $buffer = [byte[]]::new($Bytes)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buffer)
    $rng.Dispose()
    return [Convert]::ToBase64String($buffer).TrimEnd("=").Replace("+", "x").Replace("/", "y")
}

function Read-DotEnvMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trim = $line.Trim()
        if ($trim.Length -eq 0 -or $trim.StartsWith("#") -or -not $trim.Contains("=")) { continue }
        $idx = $trim.IndexOf("=")
        $key = $trim.Substring(0, $idx)
        $value = $trim.Substring($idx + 1)
        $map[$key] = $value
    }
    return $map
}

function Get-MapValue {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$Default = ""
    )
    if ($Map.Contains($Key) -and $null -ne $Map[$Key] -and "$($Map[$Key])".Length -gt 0) {
        return "$($Map[$Key])"
    }
    return $Default
}

function Get-Answer {
    param(
        [string]$Key,
        [object]$Default = $null
    )
    if ($null -ne $script:Answers -and ($script:Answers.PSObject.Properties.Name -contains $Key)) {
        $value = $script:Answers.PSObject.Properties[$Key].Value
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function Convert-ToBool {
    param([object]$Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    $raw = "$Value".Trim().ToLowerInvariant()
    if (@("1", "true", "yes", "y", "on", "enabled").Contains($raw)) { return $true }
    if (@("0", "false", "no", "n", "off", "disabled").Contains($raw)) { return $false }
    return $Default
}

function Convert-SecureStringToText {
    param([securestring]$Secure)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Show-Stage {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Show-Link {
    param([string]$Label, [string]$Url)
    Write-Host "  ${Label}: $Url" -ForegroundColor DarkCyan
}

function Ask-Text {
    param(
        [string]$Key,
        [string]$Question,
        [string]$Default = "",
        [switch]$Sensitive,
        [switch]$Required
    )
    $answer = Get-Answer $Key $null
    if ($NonInteractive) {
        if ($null -eq $answer -or "$answer".Length -eq 0) {
            if ($Required -and $Default.Length -eq 0) {
                throw "Missing required non-interactive answer: $Key"
            }
            return $Default
        }
        return "$answer"
    }

    while ($true) {
        $suffix = if ($Default.Length -gt 0) { " [$Default]" } else { "" }
        if ($Sensitive) {
            $secure = Read-Host "$Question$suffix" -AsSecureString
            $value = Convert-SecureStringToText $secure
        } else {
            $value = Read-Host "$Question$suffix"
        }
        if ($value.Length -eq 0) { $value = $Default }
        if (-not $Required -or $value.Length -gt 0) { return $value }
        Write-Host "This value is required." -ForegroundColor Yellow
    }
}

function Ask-YesNo {
    param(
        [string]$Key,
        [string]$Question,
        [bool]$Default = $false
    )
    $answer = Get-Answer $Key $null
    if ($NonInteractive) {
        return Convert-ToBool $answer $Default
    }

    $defaultText = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $raw = Read-Host "$Question [$defaultText]"
        if ($raw.Trim().Length -eq 0) { return $Default }
        $lower = $raw.Trim().ToLowerInvariant()
        if (@("y", "yes").Contains($lower)) { return $true }
        if (@("n", "no").Contains($lower)) { return $false }
        Write-Host "Please answer yes or no." -ForegroundColor Yellow
    }
}

function Ask-Choice {
    param(
        [string]$Key,
        [string]$Question,
        [string[]]$Choices,
        [string]$Default
    )
    $answer = Get-Answer $Key $null
    if ($NonInteractive) {
        $value = if ($null -eq $answer -or "$answer".Length -eq 0) { $Default } else { "$answer" }
        if (-not $Choices.Contains($value)) {
            throw "Invalid answer for ${Key}: $value. Expected one of: $($Choices -join ', ')"
        }
        return $value
    }

    while ($true) {
        Write-Host "$Question"
        for ($i = 0; $i -lt $Choices.Count; $i++) {
            $marker = if ($Choices[$i] -eq $Default) { " default" } else { "" }
            Write-Host "  $($i + 1). $($Choices[$i])$marker"
        }
        $raw = Read-Host "Choose 1-$($Choices.Count)"
        if ($raw.Trim().Length -eq 0) { return $Default }
        $num = 0
        if ([int]::TryParse($raw, [ref]$num) -and $num -ge 1 -and $num -le $Choices.Count) {
            return $Choices[$num - 1]
        }
        if ($Choices.Contains($raw)) { return $raw }
        Write-Host "Choose one of: $($Choices -join ', ')" -ForegroundColor Yellow
    }
}

function Write-DotEnv {
    param(
        [string]$BasePath,
        [string]$TargetPath,
        [hashtable]$Values
    )
    $lines = Get-Content -LiteralPath $BasePath
    $seen = @{}
    $output = foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim.Length -gt 0 -and -not $trim.StartsWith("#") -and $trim.Contains("=")) {
            $idx = $trim.IndexOf("=")
            $key = $trim.Substring(0, $idx)
            if ($Values.Contains($key)) {
                $seen[$key] = $true
                "$key=$($Values[$key])"
            } else {
                $line
            }
        } else {
            $line
        }
    }

    foreach ($key in ($Values.Keys | Sort-Object)) {
        if (-not $seen.ContainsKey($key)) {
            $output += "$key=$($Values[$key])"
        }
    }

    $parent = Split-Path -Parent $TargetPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $output | Set-Content -LiteralPath $TargetPath -Encoding utf8
}

function Test-SecretKeyName {
    param([string]$Key)
    return $Key -match "(SECRET|PASSWORD|TOKEN|API_KEY|ADMIN_KEY|PRIVATE_KEY|CLIENT_SECRET)"
}

function Write-SetupSummary {
    param(
        [string]$Path,
        [hashtable]$Values,
        [hashtable]$Runtime
    )
    $aiosUrl = "$($Values.PUBLIC_SCHEME)://$($Values.AIOSTREAMS_HOST)"
    $metaUrl = "$($Values.PUBLIC_SCHEME)://$($Values.AIOMETADATA_HOST)"
    $nzbUrl = "$($Values.PUBLIC_SCHEME)://$($Values.NZBDAV_HOST)"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Setup Summary")
    $lines.Add("")
    $lines.Add("Generated: $(Get-Date -Format o)")
    $lines.Add("")
    $lines.Add("## Public URLs")
    $lines.Add("")
    $lines.Add("- AIOStreams: $aiosUrl/stremio/configure")
    $lines.Add("- AIOMetadata: $metaUrl/configure")
    if ((Convert-ToBool $Values.NZBDAV_ENABLED $false)) {
        $lines.Add("- NzbDav: $nzbUrl")
    }
    $lines.Add("")
    $lines.Add("## Selected Components")
    $lines.Add("")
    $lines.Add("- AIOStreams: $($Values.AIOSTREAMS_ENABLED)")
    $lines.Add("- AIOMetadata: $($Values.AIOMETADATA_ENABLED)")
    $lines.Add("- NzbDav: $($Values.NZBDAV_ENABLED)")
    $lines.Add("- VPN mode: $($Values.VPN_MODE)")
    $lines.Add("- Include Nginx Proxy Manager service: $($Values.ENABLE_NPM_SERVICE)")
    $lines.Add("- Create NPM proxy hosts: $($Values.NPM_CREATE_PROXY_HOSTS)")
    $lines.Add("- Deployment mode: $($Runtime.deploymentMode)")
    $lines.Add("")
    $lines.Add("## Config Values")
    $lines.Add("")
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = if (Test-SecretKeyName $key) {
            if ("$($Values[$key])".Length -gt 0) { "[set]" } else { "[empty]" }
        } else {
            "$($Values[$key])"
        }
        $lines.Add("- ${key}: $value")
    }
    $lines.Add("")
    $lines.Add("## Docs")
    $lines.Add("")
    $lines.Add("- AIOStreams deployment: https://docs.aiostreams.viren070.me/getting-started/deployment/")
    $lines.Add("- AIOStreams environment variables: https://docs.aiostreams.viren070.me/configuration/environment-variables/")
    $lines.Add("- AIOMetadata environment variables: https://github.com/cedya77/aiometadata/blob/main/docs/ENVIRONMENT_VARIABLES.md")
    $lines.Add("- NzbDav setup: https://raw.githubusercontent.com/nzbdav-dev/nzbdav/main/docs/setup-guide.md")
    $lines.Add("- Gluetun HTTP proxy: https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/options/http-proxy.md")
    $lines.Add("- Nginx Proxy Manager setup: https://nginxproxymanager.com/setup/")
    $lines.Add("")
    $lines.Add("## Next Steps")
    $lines.Add("")
    $lines.Add("1. Review the rendered files in `rendered/`.")
    $lines.Add("2. Deploy with Portainer or SSH if you did not deploy during setup.")
    $lines.Add("3. Open each app URL above and finish first-run UI configuration.")

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $lines | Set-Content -LiteralPath $Path -Encoding utf8
}

if ($NonInteractive -and -not $AnswersPath) {
    throw "-AnswersPath is required with -NonInteractive."
}
if ($AnswersPath) {
    if (-not (Test-Path -LiteralPath $AnswersPath)) { throw "Answers file not found: $AnswersPath" }
    $script:Answers = Get-Content -Raw -LiteralPath $AnswersPath | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $ExamplePath)) {
    throw "Example config not found: $ExamplePath"
}

$basePath = if ((Test-Path -LiteralPath $ConfigPath) -and -not $Force) { $ConfigPath } else { $ExamplePath }
$current = Read-DotEnvMap $basePath

Show-Stage "Stremio Self-Hosted Stack Setup"
Write-Host "This wizard writes $ConfigPath, renders Docker Compose, and can optionally deploy over SSH."
Write-Host "Secrets are stored in $ConfigPath, which is gitignored by this repo."
Show-Link "Prerequisites Guide" "docs/prerequisites.md"
Show-Link "Runbook" "https://github.com/ZaneStephens/stremio-selfhost-stack/blob/main/docs/runbook.md"

$hasPrereqs = Ask-YesNo "readPrerequisites" "Have you read the prerequisites in docs/prerequisites.md and configured your domain/DNS/server?" $true
if (-not $hasPrereqs) {
    Write-Host ""
    Write-Host "Please complete the prerequisites before running this setup." -ForegroundColor Yellow
    Write-Host "Read the guide here: docs/prerequisites.md" -ForegroundColor Cyan
    Write-Host "Exiting setup."
    return
}


Show-Stage "Domain and URLs"
Show-Link "Nginx Proxy Manager setup" "https://nginxproxymanager.com/setup/"
Show-Link "Portainer stacks" "https://docs.portainer.io/user/docker/stacks/add"
$publicScheme = Ask-Choice "publicScheme" "Public URL scheme" @("https", "http") (Get-MapValue $current "PUBLIC_SCHEME" "https")
$baseDomain = Ask-Text "baseDomain" "Base domain" (Get-MapValue $current "BASE_DOMAIN" "example.com") -Required
$aiosHostDefault = Get-MapValue $current "AIOSTREAMS_HOST" "aiostreams.$baseDomain"
$metaHostDefault = Get-MapValue $current "AIOMETADATA_HOST" "metadata.$baseDomain"
$nzbHostDefault = Get-MapValue $current "NZBDAV_HOST" "nzbdav.$baseDomain"
if ($aiosHostDefault -eq "aiostreams.example.com") { $aiosHostDefault = "aiostreams.$baseDomain" }
if ($metaHostDefault -eq "metadata.example.com") { $metaHostDefault = "metadata.$baseDomain" }
if ($nzbHostDefault -eq "nzbdav.example.com") { $nzbHostDefault = "nzbdav.$baseDomain" }
$aiosHost = Ask-Text "aiostreamsHost" "AIOStreams hostname" $aiosHostDefault -Required
$metaHost = Ask-Text "aiometadataHost" "AIOMetadata hostname" $metaHostDefault -Required
$nzbHost = Ask-Text "nzbdavHost" "NzbDav hostname" $nzbHostDefault -Required
$email = Ask-Text "letsEncryptEmail" "Let's Encrypt email" (Get-MapValue $current "LETSENCRYPT_EMAIL" "you@example.com") -Required

Show-Stage "Core Services"
Show-Link "AIOStreams deployment" "https://docs.aiostreams.viren070.me/getting-started/deployment/"
Show-Link "AIOMetadata self-hosting" "https://github.com/cedya77/aiometadata/blob/main/docs/self-hosting.md"
$aiosUser = Ask-Text "aiostreamsAuthUser" "AIOStreams admin username" (Get-MapValue $current "AIOSTREAMS_AUTH_USER" "admin") -Required
$existingAiosPassword = Get-MapValue $current "AIOSTREAMS_AUTH_PASSWORD" ""
$aiosPassword = Ask-Text "aiostreamsAuthPassword" "AIOStreams admin password, blank generates one" $existingAiosPassword -Sensitive
if ($aiosPassword.Length -eq 0) { $aiosPassword = New-Password }

Show-Stage "API Keys"
Write-Host "You can leave optional provider keys blank and add them later in config/stack.env."
Show-Link "TMDB API key" "https://www.themoviedb.org/settings/api"
Show-Link "TVDB API key" "https://thetvdb.com/dashboard/account/apikeys"
Show-Link "Fanart.tv API key" "https://fanart.tv/get-an-api-key/"
Show-Link "MDBList API key" "https://mdblist.com/"
Show-Link "Trakt applications" "https://trakt.tv/oauth/applications"
Show-Link "SimKL applications" "https://simkl.com/oauth/applications"
Show-Link "Gemini API key" "https://makersuite.google.com/app/apikey"
$tmdbKey = Ask-Text "tmdbApiKey" "TMDB API key, recommended before deploy" (Get-MapValue $current "TMDB_API_KEY" "") -Sensitive
$tvdbKey = Ask-Text "tvdbApiKey" "TVDB API key, optional" (Get-MapValue $current "TVDB_API_KEY" "") -Sensitive
$fanartKey = Ask-Text "fanartApiKey" "Fanart.tv API key, optional" (Get-MapValue $current "FANART_API_KEY" "") -Sensitive
$rpdbKey = Ask-Text "rpdbApiKey" "RPDB API key, optional" (Get-MapValue $current "RPDB_API_KEY" "") -Sensitive
$mdblistKey = Ask-Text "mdblistApiKey" "MDBList API key, optional" (Get-MapValue $current "MDBLIST_API_KEY" "") -Sensitive
$traktId = Ask-Text "traktClientId" "Trakt client ID, optional" (Get-MapValue $current "TRAKT_CLIENT_ID" "") -Sensitive
$traktSecret = Ask-Text "traktClientSecret" "Trakt client secret, optional" (Get-MapValue $current "TRAKT_CLIENT_SECRET" "") -Sensitive
$simklId = Ask-Text "simklClientId" "SimKL client ID, optional" (Get-MapValue $current "SIMKL_CLIENT_ID" "") -Sensitive
$simklSecret = Ask-Text "simklClientSecret" "SimKL client secret, optional" (Get-MapValue $current "SIMKL_CLIENT_SECRET" "") -Sensitive
$geminiKey = Ask-Text "geminiApiKey" "Gemini API key, optional" (Get-MapValue $current "GEMINI_API_KEY" "") -Sensitive

Show-Stage "Optional NzbDav"
Show-Link "NzbDav setup guide" "https://raw.githubusercontent.com/nzbdav-dev/nzbdav/main/docs/setup-guide.md"
Show-Link "AIOStreams Usenet guide" "https://github.com/Viren070/AIOStreams/wiki/Usenet"
$enableNzbDav = Ask-YesNo "enableNzbDav" "Include self-hosted NzbDav?" (Convert-ToBool (Get-MapValue $current "NZBDAV_ENABLED" "false") $false)
$enableRclone = $false
if ($enableNzbDav) {
    $enableRclone = Ask-YesNo "nzbdavEnableRclone" "Enable NzbDav rclone sidecar later? Current renderer records the choice only." (Convert-ToBool (Get-MapValue $current "NZBDAV_ENABLE_RCLONE" "false") $false)
}

Show-Stage "VPN and Gluetun"
Show-Link "Gluetun HTTP proxy" "https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/options/http-proxy.md"
Show-Link "Gluetun container routing" "https://raw.githubusercontent.com/qdm12/gluetun-wiki/main/setup/connect-a-container-to-gluetun.md"
$vpnChoices = if ($enableNzbDav) { @("off", "http-proxy", "hybrid") } else { @("off", "http-proxy") }
$vpnDefault = Get-MapValue $current "VPN_MODE" "off"
if (-not $vpnChoices.Contains($vpnDefault)) { $vpnDefault = "off" }
$vpnMode = Ask-Choice "vpnMode" "VPN mode" $vpnChoices $vpnDefault
$gluetunProvider = Get-MapValue $current "GLUETUN_VPN_SERVICE_PROVIDER" ""
$gluetunType = Get-MapValue $current "GLUETUN_VPN_TYPE" "wireguard"
$gluetunPrivateKey = Get-MapValue $current "GLUETUN_WIREGUARD_PRIVATE_KEY" ""
$gluetunAddresses = Get-MapValue $current "GLUETUN_WIREGUARD_ADDRESSES" ""
$gluetunCountries = Get-MapValue $current "GLUETUN_SERVER_COUNTRIES" ""
$openVpnUser = Get-MapValue $current "GLUETUN_OPENVPN_USER" ""
$openVpnPassword = Get-MapValue $current "GLUETUN_OPENVPN_PASSWORD" ""
if ($vpnMode -ne "off") {
    $gluetunProvider = Ask-Text "gluetunVpnServiceProvider" "Gluetun VPN service provider" $gluetunProvider
    $gluetunType = Ask-Choice "gluetunVpnType" "Gluetun VPN type" @("wireguard", "openvpn") $gluetunType
    $gluetunCountries = Ask-Text "gluetunServerCountries" "Gluetun server countries, optional" $gluetunCountries
    if ($gluetunType -eq "wireguard") {
        $gluetunPrivateKey = Ask-Text "gluetunWireguardPrivateKey" "WireGuard private key" $gluetunPrivateKey -Sensitive
        $gluetunAddresses = Ask-Text "gluetunWireguardAddresses" "WireGuard addresses" $gluetunAddresses
    } else {
        $openVpnUser = Ask-Text "gluetunOpenVpnUser" "OpenVPN username" $openVpnUser -Sensitive
        $openVpnPassword = Ask-Text "gluetunOpenVpnPassword" "OpenVPN password" $openVpnPassword -Sensitive
    }
}

Show-Stage "Nginx Proxy Manager"
Show-Link "NPM setup" "https://nginxproxymanager.com/setup/"
$npmModeDefault = if ((Convert-ToBool (Get-MapValue $current "ENABLE_NPM_SERVICE" "false") $false)) { "include" } else { "existing" }
$npmMode = Ask-Choice "npmMode" "Nginx Proxy Manager mode" @("existing", "include", "skip") $npmModeDefault
$enableNpmService = $npmMode -eq "include"
$createProxyHosts = $false
$npmContainer = Get-MapValue $current "NPM_CONTAINER_NAME" "nginx-proxy-manager"
$npmBaseUrl = Get-MapValue $current "NPM_BASE_URL" "http://127.0.0.1:81"
$npmIdentity = Get-MapValue $current "NPM_IDENTITY" "admin@example.com"
$npmSecret = Get-MapValue $current "NPM_SECRET" "changeme"
if ($npmMode -ne "skip") {
    $npmContainer = Ask-Text "npmContainerName" "NPM container name" $npmContainer
    $npmBaseUrl = Ask-Text "npmBaseUrl" "NPM admin/API URL" $npmBaseUrl
    $createProxyHosts = Ask-YesNo "npmCreateProxyHosts" "Let the script create missing NPM proxy hosts?" (Convert-ToBool (Get-MapValue $current "NPM_CREATE_PROXY_HOSTS" "true") $true)
    if ($createProxyHosts) {
        $npmIdentity = Ask-Text "npmIdentity" "NPM admin email" $npmIdentity
        $npmSecret = Ask-Text "npmSecret" "NPM admin password" $npmSecret -Sensitive
    }
}

Show-Stage "Deployment"
$deploymentMode = Ask-Choice "deploymentMode" "What should setup do after rendering?" @("render", "portainer", "ssh") "render"
$sshHost = ""
$sshUser = "ubuntu"
$sshKey = ""
$remoteDir = "/opt/stremio-stack"
if ($deploymentMode -eq "ssh") {
    $sshHost = Ask-Text "sshHost" "SSH host or IP" "" -Required
    $sshUser = Ask-Text "sshUser" "SSH user" "ubuntu" -Required
    $sshKey = Ask-Text "sshKey" "SSH key path, optional" ""
    $remoteDir = Ask-Text "remoteDir" "Remote deploy directory" "/opt/stremio-stack" -Required
}

$values = [ordered]@{
    PUBLIC_SCHEME = $publicScheme
    BASE_DOMAIN = $baseDomain
    AIOSTREAMS_HOST = $aiosHost
    AIOMETADATA_HOST = $metaHost
    NZBDAV_HOST = $nzbHost
    TZ = Get-MapValue $current "TZ" "Australia/Sydney"
    DATA_ROOT = Get-MapValue $current "DATA_ROOT" "/opt/stremio-stack/data"
    PUID = Get-MapValue $current "PUID" "1000"
    PGID = Get-MapValue $current "PGID" "1000"
    AIOSTREAMS_ENABLED = "true"
    AIOSTREAMS_SECRET_KEY = Get-MapValue $current "AIOSTREAMS_SECRET_KEY" (New-HexSecret 32)
    AIOSTREAMS_AUTH_USER = $aiosUser
    AIOSTREAMS_AUTH_PASSWORD = $aiosPassword
    AIOMETADATA_ENABLED = "true"
    AIOMETADATA_ADMIN_KEY = Get-MapValue $current "AIOMETADATA_ADMIN_KEY" (New-HexSecret 32)
    TMDB_API_KEY = $tmdbKey
    TVDB_API_KEY = $tvdbKey
    FANART_API_KEY = $fanartKey
    RPDB_API_KEY = $rpdbKey
    MDBLIST_API_KEY = $mdblistKey
    TRAKT_CLIENT_ID = $traktId
    TRAKT_CLIENT_SECRET = $traktSecret
    SIMKL_CLIENT_ID = $simklId
    SIMKL_CLIENT_SECRET = $simklSecret
    GEMINI_API_KEY = $geminiKey
    NZBDAV_ENABLED = if ($enableNzbDav) { "true" } else { "false" }
    NZBDAV_ENABLE_RCLONE = if ($enableRclone) { "true" } else { "false" }
    VPN_MODE = $vpnMode
    GLUETUN_VPN_SERVICE_PROVIDER = $gluetunProvider
    GLUETUN_VPN_TYPE = $gluetunType
    GLUETUN_SERVER_COUNTRIES = $gluetunCountries
    GLUETUN_WIREGUARD_PRIVATE_KEY = $gluetunPrivateKey
    GLUETUN_WIREGUARD_ADDRESSES = $gluetunAddresses
    GLUETUN_OPENVPN_USER = $openVpnUser
    GLUETUN_OPENVPN_PASSWORD = $openVpnPassword
    ENABLE_NPM_SERVICE = if ($enableNpmService) { "true" } else { "false" }
    NPM_CONTAINER_NAME = $npmContainer
    NPM_BASE_URL = $npmBaseUrl
    NPM_IDENTITY = $npmIdentity
    NPM_SECRET = $npmSecret
    NPM_CREATE_PROXY_HOSTS = if ($createProxyHosts) { "true" } else { "false" }
    LETSENCRYPT_EMAIL = $email
}

Write-DotEnv -BasePath $basePath -TargetPath $ConfigPath -Values $values
Write-Host ""
Write-Host "Wrote $ConfigPath" -ForegroundColor Green

if (-not $NonInteractive -and -not $NoEdit) {
    $edit = Ask-YesNo "editConfigBeforeRender" "Open config for manual review before rendering?" $false
    if ($edit) {
        $isWindowsHost = [Environment]::OSVersion.Platform -eq "Win32NT"
        if ($isWindowsHost) {
            notepad $ConfigPath
        } else {
            Write-Host "Edit this file in another terminal, then press Enter to continue: $ConfigPath"
            Read-Host "Press Enter when ready" | Out-Null
        }
    }
}

$confirmRender = Ask-YesNo "confirmRender" "Render docker-compose.yml now?" $true
if ($SkipRender) { $confirmRender = $false }
if ($confirmRender) {
    & "$PSScriptRoot\render-stack.ps1" -ConfigPath $ConfigPath -OutputDir $RenderOutputDir
}

$runtime = @{
    deploymentMode = $deploymentMode
}
Write-SetupSummary -Path (Join-Path $RenderOutputDir "setup-summary.md") -Values $values -Runtime $runtime
Write-Host "Wrote $(Join-Path $RenderOutputDir 'setup-summary.md')" -ForegroundColor Green

if ($deploymentMode -eq "ssh" -and -not $SkipDeploy) {
    $deployArgs = @("-SshHost", $sshHost, "-User", $sshUser, "-RemoteDir", $remoteDir, "-SkipRender")
    if ($sshKey.Length -gt 0) { $deployArgs += @("-SshKey", $sshKey) }
    & "$PSScriptRoot\deploy-ssh.ps1" @deployArgs
}
elseif ($deploymentMode -eq "portainer") {
    Write-Host ""
    Write-Host "Portainer deploy path:"
    Write-Host "  1. Open Portainer > Stacks > Add stack."
    Write-Host "  2. Paste or upload $(Join-Path $RenderOutputDir 'docker-compose.yml')."
    Write-Host "  3. Deploy the stack."
}

if ($createProxyHosts -and -not $SkipNpm) {
    $runNpm = if ($NonInteractive) { Convert-ToBool (Get-Answer "runNpmConfig" $false) $false } else { Ask-YesNo "runNpmConfig" "Run NPM proxy-host creation now?" $false }
    if ($runNpm) {
        & "$PSScriptRoot\configure-npm.ps1" -ConfigPath $ConfigPath -ProxyHostsPath (Join-Path $RenderOutputDir "proxy-hosts.json")
    }
}

Write-Host ""
Write-Host "Setup workflow complete. Review $(Join-Path $RenderOutputDir 'setup-summary.md') for URLs and next steps." -ForegroundColor Green
