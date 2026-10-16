[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Workspace.ps1')
Assert-AutoIt
if ($script:WorkspaceRoot -match '[^\x00-\x7F]') {
    throw 'Au3Check has Unicode include-path limitations. Use an ASCII workspace path, for example D:\AutoDeploy (spaces are supported).'
}
$failed = $false
foreach ($file in Get-ChildItem -LiteralPath $script:WorkspaceRoot -Recurse -Filter '*.ps1' | Where-Object { $_.FullName.Substring($script:WorkspaceRoot.Length + 1) -notmatch '^(tools|artifacts|logs)\\' }) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { $parseErrors | Write-Host; $failed = $true }
}
foreach ($file in Get-ChildItem -LiteralPath (Resolve-WorkspacePath 'config') -Recurse -Filter '*.json') { $null = Read-JsonFile $file.FullName }
foreach ($file in Get-ChildItem -LiteralPath (Resolve-WorkspacePath 'config/profiles') -Filter '*.json') { $null = @(Get-DeploymentPlan $file.BaseName @()) }
$checker = Resolve-WorkspacePath 'tools/autoit/install/Au3Check.exe'
$sources = @(Get-ChildItem -LiteralPath (Resolve-WorkspacePath 'scripts/modules') -Filter '*.au3')
# The template include is relative to its destination under scripts/modules.
foreach ($file in $sources) {
    $result = Invoke-CapturedProcess $checker ('-q -w 1 -w 2 "' + $file.FullName + '"') 60
    Write-Host "$($file.Name): $($result.Output.Trim())"
    if ($result.Code -ne 0) { $failed = $true }
}
if ($failed) { throw 'Workspace checks failed.' }
Write-Host 'PowerShell syntax, JSON/profiles and AutoIt modules passed. No installer started.'
