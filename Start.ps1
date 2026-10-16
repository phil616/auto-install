[CmdletBinding(DefaultParameterSetName = 'Preview')]
param(
    [string]$Profile = 'dev',
    [string[]]$Only = @(),
    [Parameter(ParameterSetName = 'Execute')][switch]$Execute,
    [Parameter(ParameterSetName = 'Validate')][switch]$Validate
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts/lib/Workspace.ps1')
$lock = $null
try {
    $plan = @(Get-DeploymentPlan $Profile $Only)
    Write-Host "Profile=$Profile; plugins=$($plan.Count); Execute=$Execute"
    foreach ($item in $plan) {
        $state = if ($item.Issues.Count) { $item.Issues -join '; ' } else { 'configuration complete (run -Validate to check hashes)' }
        Write-Host ("  {0}: {1}; admin={2}; {3}" -f $item.Id, $item.Plugin.version, $item.Plugin.requiresAdmin, $state)
    }
    if (-not $Execute -and -not $Validate) { Write-Host 'Preview only. No installer started.'; exit 0 }
    Assert-AutoIt
    Assert-DeploymentReady $plan
    if ($Validate) { Write-Host 'Preflight passed. No installer started.'; exit 0 }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (@($plan | Where-Object { $_.Plugin.requiresAdmin }).Count -gt 0 -and -not $isAdmin) { throw 'This profile needs an elevated PowerShell window. No installer started.' }
    $logRoot = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $lock = [IO.File]::Open((Join-Path $logRoot '.deployment.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $runDir = Join-Path $logRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $runDir | Out-Null
    $results = @($plan | ForEach-Object { [pscustomobject]@{ id = $_.Id; version = $_.Plugin.version; status = 'pending'; exitCode = $null; finishedAt = $null } })
    $summary = Join-Path $runDir 'results.json'
    ConvertTo-Json -InputObject $results -Depth 5 | Set-Content -LiteralPath $summary -Encoding UTF8
    $exitCode = 0
    for ($i = 0; $i -lt $plan.Count; $i++) {
        $item = $plan[$i]
        $plugin = $item.Plugin
        $appLog = Join-Path $runDir $item.Id
        New-Item -ItemType Directory -Path $appLog | Out-Null
        try {
            if ($plugin.skipIfVerified -and (Test-PluginInstalled $plugin)) {
                $results[$i].status = 'skipped-verified'
                $results[$i].exitCode = 0
            } else {
                # Recheck the selected package immediately before execution.
                if ((Get-FileHash -LiteralPath $item.PackagePath -Algorithm SHA256).Hash -ine $plugin.sha256) { throw 'Package changed after preflight.' }
                $environment = @{
                    DEPLOY_ROOT = $PSScriptRoot
                    DEPLOY_PACKAGE = $item.PackagePath
                    DEPLOY_ARGUMENTS = ([Environment]::ExpandEnvironmentVariables($plugin.arguments)).Replace('{logDir}', $appLog)
                    DEPLOY_TARGET = [Environment]::ExpandEnvironmentVariables($plugin.targetDir)
                    DEPLOY_TIMEOUT = [string]$plugin.timeoutSeconds
                    DEPLOY_LOG_DIR = $appLog
                }
                Write-Host "Installing $($item.Id)..."
                $result = Invoke-CapturedProcess (Get-AutoItPath) ('/ErrorStdOut "' + $item.ModulePath + '"') ($plugin.timeoutSeconds + 30) $environment
                $result.Output | Set-Content -LiteralPath (Join-Path $appLog 'module.log') -Encoding UTF8
                $results[$i].exitCode = $result.Code
                if ($result.Code -in @(3010,1641)) {
                    $results[$i].status = 'reboot-required'
                    $exitCode = $result.Code
                } elseif ($result.Code -ne 0) {
                    throw "Module failed with exit $($result.Code). See $appLog"
                } elseif (-not (Test-PluginInstalled $plugin)) {
                    throw "Post-install verification failed. See $appLog"
                } else { $results[$i].status = 'installed-verified' }
            }
        } catch {
            $results[$i].status = 'failed'
            if ($null -eq $results[$i].exitCode -or $results[$i].exitCode -eq 0) { $results[$i].exitCode = 1 }
            $_ | Out-String | Set-Content -LiteralPath (Join-Path $appLog 'error.log') -Encoding UTF8
            Write-Warning $_.Exception.Message
            $exitCode = $results[$i].exitCode
        }
        $results[$i].finishedAt = (Get-Date).ToString('o')
        ConvertTo-Json -InputObject $results -Depth 5 | Set-Content -LiteralPath $summary -Encoding UTF8
        if ($exitCode -ne 0) { break }
    }
    Write-Host "Results: $summary"
    if ($exitCode -in @(124,3010,1641)) { Write-Warning 'Queue stopped. Inspect the machine/logs before continuing; no automatic retry.' }
    exit $exitCode
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally { if ($null -ne $lock) { $lock.Dispose() } }
