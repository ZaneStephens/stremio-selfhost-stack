[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Host,
    [string]$User = "ubuntu",
    [string]$RemoteDir = "/opt/stremio-stack",
    [string]$RemoteDataDir = "/opt/stremio-stack/data",
    [string]$LocalBackupDir = "backups",
    [string]$SshKey = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $LocalBackupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteTar = "/tmp/stremio-stack-backup-$stamp.tgz"
$target = "$User@$Host"
$sshArgs = @()
$scpArgs = @()
if ($SshKey) {
    $sshArgs += @("-i", $SshKey)
    $scpArgs += @("-i", $SshKey)
}

& ssh @sshArgs $target "sudo tar -czf '$remoteTar' -C '$RemoteDir' docker-compose.yml -C '$RemoteDataDir' ."
if ($LASTEXITCODE -ne 0) { throw "Remote backup failed." }

$localPath = Join-Path $LocalBackupDir "stremio-stack-backup-$stamp.tgz"
& scp @scpArgs "$target`:$remoteTar" $localPath
if ($LASTEXITCODE -ne 0) { throw "Backup download failed." }

& ssh @sshArgs $target "rm -f '$remoteTar'"
Write-Host "Backup saved to $localPath"
