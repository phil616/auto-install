[CmdletBinding()]
param([switch]$MsiCompatibilityWorkaround)
$ErrorActionPreference = 'Stop'
# This script must never install software on the host.
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path -LiteralPath 'C:\AutoDeployInput\Start.ps1')) {
    throw 'This entry point only runs as WDAGUtilityAccount inside the configured Windows Sandbox.'
}
$output = 'C:\AutoDeployOutput'
$work = 'C:\AutoDeployTest'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$report = [ordered]@{ startedAt=(Get-Date).ToString('o'); computer=$env:COMPUTERNAME; user=$env:USERNAME; status='running'; steps=@(); error=$null }
function Save-Report { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'sandbox-report.json') -Encoding UTF8 }
Save-Report
try {
    Copy-Item -Path 'C:\AutoDeployInput\*' -Destination $work -Recurse -Force
    . (Join-Path $work 'scripts/lib/Workspace.ps1')
    $baseline = [ordered]@{
        git = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
        uv = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.local\bin\uv.exe')
        rustpm = $null -ne (Get-Service -Name rustpm -ErrorAction SilentlyContinue)
    }
    $report.baseline = $baseline
    Save-Report
    if ($baseline.git -or $baseline.uv -or $baseline.rustpm) { throw 'Sandbox is not clean; refusing an upgrade-based installation test.' }
    if ($MsiCompatibilityWorkaround) {
        $report.msiCompatibility = & (Join-Path $work 'scripts/Sandbox-MsiCompatibility.ps1')
        Save-Report
    }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($id in @('git','uv','vc-runtime-x64','custom-msi')) {
        $result = Invoke-CapturedProcess $powershell ('-NoProfile -ExecutionPolicy Bypass -File "' + $work + '\Start.ps1" -Profile dev -Only ' + $id + ' -Execute') 1900
        $result.Output | Set-Content -LiteralPath (Join-Path $output ($id + '-runner.log')) -Encoding UTF8
        $report.steps += [ordered]@{ id=$id; exitCode=$result.Code; finishedAt=(Get-Date).ToString('o') }
        Save-Report
        if ($result.Code -ne 0) { throw "Plugin $id failed with exit $($result.Code)." }
    }
    # A newly opened terminal reloads both persistent PATH scopes.
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    foreach ($spec in @(@('git.exe','--version'),@('uv.exe','--version'),@('uvx.exe','--version'),@('rustpmctl.exe','--help'))) {
        $command = Get-Command $spec[0] -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $result = Invoke-CapturedProcess $command.Source $spec[1] 30
        $result.Output | Set-Content -LiteralPath (Join-Path $output ($spec[0] + '-check.log')) -Encoding UTF8
        if ($result.Code -ne 0) { throw "CLI verification failed: $($spec[0])" }
    }
    $report.status = 'passed'
} catch {
    $report.status = 'failed'
    $report.error = $_.Exception.Message
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $output 'guest-error.log') -Encoding UTF8
} finally {
    if (Test-Path -LiteralPath (Join-Path $work 'logs')) { Copy-Item -LiteralPath (Join-Path $work 'logs') -Destination (Join-Path $output 'deployment-logs') -Recurse -Force }
    $report.finishedAt = (Get-Date).ToString('o')
    Save-Report
}
