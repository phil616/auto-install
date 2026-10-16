[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/lib/Workspace.ps1')
Assert-AutoIt
$tag = 'smoke-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$fixtureDir = Resolve-WorkspacePath "logs/$tag"
$moduleRelative = "scripts/modules/$tag.au3"
$modulePath = Resolve-WorkspacePath $moduleRelative
$profilePath = Resolve-WorkspacePath "config/profiles/$tag.json"
$pluginPaths = @((Resolve-WorkspacePath "config/plugins/$tag-a.json"), (Resolve-WorkspacePath "config/plugins/$tag-b.json"))
New-Item -ItemType Directory -Path $fixtureDir | Out-Null
$package = Join-Path $fixtureDir 'fixture.txt'
'Harmless test fixture; not an installer.' | Set-Content -LiteralPath $package -Encoding UTF8
$packageRelative = "logs/$tag/fixture.txt"
$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
$markerA = Join-Path $fixtureDir '已验证 A.txt'
$markerB = Join-Path $fixtureDir 'verified-b.txt'
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$checks = 0
function Write-FixturePlugin([int]$Index, [string]$Mode = '0', [string]$HashValue = $hash) {
    $id = if ($Index -eq 0) { "$tag-a" } else { "$tag-b" }
    $marker = if ($Index -eq 0) { $markerA } else { $markerB }
    $plugin = [ordered]@{
        id = $id; version = '1.0-test'; module = $moduleRelative; package = $packageRelative
        sha256 = $HashValue; architecture = 'any'; requiresAdmin = $false; timeoutSeconds = 10
        arguments = $Mode; targetDir = $marker; skipIfVerified = $false
        verify = @{ path = $marker; arguments = ''; contains = '' }
    }
    $plugin | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $pluginPaths[$Index] -Encoding UTF8
}
function Run-Fixture([string]$Switch, [int]$Expected) {
    $result = Invoke-CapturedProcess $powershell ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $script:WorkspaceRoot 'Start.ps1') + '" -Profile ' + $tag + ' ' + $Switch) 60
    if ($result.Code -ne $Expected) { throw "Expected exit $Expected, got $($result.Code): $($result.Output)" }
    $script:checks++
}
function Clear-Markers {
    foreach ($path in @($markerA,$markerB)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
}
try {
    @'
#include "..\lib\Common.au3"
Local $sMode = EnvGet("DEPLOY_ARGUMENTS")
If $sMode <> "no-marker" Then FileWrite(_RequiredEnv("DEPLOY_TARGET"), "fixture")
If $sMode = "no-marker" Then Exit 0
If $sMode = "timeout" Then Exit _Wait(_Start(@ComSpec & ' /c ping.exe 127.0.0.1 -n 4 >nul'), 1)
; Long command lines and fast processes must preserve the exit code.
Exit _Exec(@ComSpec & ' /c ' & StringFormat("%400s", " ") & 'exit /b ' & $sMode)
'@ | Set-Content -LiteralPath $modulePath -Encoding UTF8
    @{ name = $tag; plugins = @("$tag-a","$tag-b") } | ConvertTo-Json | Set-Content -LiteralPath $profilePath -Encoding UTF8
    Write-FixturePlugin 0
    Write-FixturePlugin 1
    Run-Fixture '' 0
    if (Test-Path -LiteralPath $markerA) { throw 'Preview executed a module.' }
    Run-Fixture '-Validate' 0
    Run-Fixture '-Execute' 0
    if (-not (Test-Path -LiteralPath $markerA) -or -not (Test-Path -LiteralPath $markerB)) { throw 'Sequential successful modules did not both execute.' }
    Clear-Markers
    Write-FixturePlugin 1 '0' ('0' * 64)
    Run-Fixture '-Execute' 1
    if (Test-Path -LiteralPath $markerA) { throw 'Preflight failed to stop all execution on a later package hash mismatch.' }
    Write-FixturePlugin 1
    Write-FixturePlugin 0 '1'
    Run-Fixture '-Execute' 1
    if (Test-Path -LiteralPath $markerB) { throw 'Queue continued after failure.' }
    Clear-Markers
    Write-FixturePlugin 0 'no-marker'
    Run-Fixture '-Execute' 1
    if (Test-Path -LiteralPath $markerB) { throw 'Queue continued after failed verification.' }
    Write-FixturePlugin 0 '3010'
    Run-Fixture '-Execute' 3010
    if (Test-Path -LiteralPath $markerB) { throw 'Queue continued after a reboot request.' }
    Clear-Markers
    Write-FixturePlugin 0 'timeout'
    Run-Fixture '-Execute' 124
    if (Test-Path -LiteralPath $markerB) { throw 'Queue continued after timeout.' }
    Write-Host "$checks smoke scenarios passed using Windows PowerShell 5.1 and AutoIt. No real software installed."
    Write-Host "Fixture evidence: $fixtureDir"
} finally {
    # Only delete the exact temporary config/module files created by this run.
    foreach ($path in (@($profilePath,$modulePath) + $pluginPaths)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
}
