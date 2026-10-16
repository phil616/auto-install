[CmdletBinding()]
param([string]$Profile = 'dev', [switch]$SkipArchive)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Workspace.ps1')
$plan = @(Get-DeploymentPlan $Profile @())
Assert-AutoIt
Assert-DeploymentReady $plan
$name = $Profile + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$destination = Resolve-WorkspacePath "artifacts/$name"
New-Item -ItemType Directory -Path $destination | Out-Null
foreach ($folder in @('scripts','docs')) { Copy-Item -LiteralPath (Resolve-WorkspacePath $folder) -Destination (Join-Path $destination $folder) -Recurse }
foreach ($folder in @('config/profiles','config/plugins','tools/autoit','packages','logs')) { New-Item -ItemType Directory -Path (Join-Path $destination $folder) -Force | Out-Null }
foreach ($file in @('Start.ps1','README.md','tools/autoit.lock.json','tools/packages.lock.json')) { Copy-Item -LiteralPath (Resolve-WorkspacePath $file) -Destination (Join-Path $destination $file) }
Copy-Item -LiteralPath (Resolve-WorkspacePath "config/profiles/$Profile.json") -Destination (Join-Path $destination "config/profiles/$Profile.json")
Copy-Item -LiteralPath (Resolve-WorkspacePath 'tools/autoit/install') -Destination (Join-Path $destination 'tools/autoit/install') -Recurse
foreach ($item in $plan) {
    Copy-Item -LiteralPath (Resolve-WorkspacePath "config/plugins/$($item.Id).json") -Destination (Join-Path $destination "config/plugins/$($item.Id).json")
    $target = Join-Path $destination $item.Plugin.package
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $item.PackagePath -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $item.Plugin.sha256) { throw "Copied package hash mismatch: $($item.Id)" }
}
# Carry custom module dependencies with the scripts tree; never include other profiles/packages/logs.
@"
@echo off
setlocal
cd /d "%~dp0"
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start.ps1" -Profile $Profile %*
exit /b %errorlevel%
"@ | Set-Content -LiteralPath (Join-Path $destination 'Run.cmd') -Encoding ASCII
$manifest = @(Get-ChildItem -LiteralPath $destination -Recurse -File | ForEach-Object {
    [pscustomobject]@{ path = $_.FullName.Substring($destination.Length + 1); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
ConvertTo-Json -InputObject $manifest -Depth 4 | Set-Content -LiteralPath (Join-Path $destination 'bundle-manifest.json') -Encoding UTF8
Write-Host "Folder: $destination"
if (-not $SkipArchive) {
    $zip = $destination + '.zip'
    Compress-Archive -Path (Join-Path $destination '*') -DestinationPath $zip
    Write-Host "ZIP: $zip"
}
