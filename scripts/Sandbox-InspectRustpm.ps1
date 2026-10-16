[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path 'C:\AutoDeployInput\Start.ps1')) { throw 'Sandbox only.' }
. 'C:\AutoDeployTest\scripts\lib\Workspace.ps1'
$output = 'C:\AutoDeployOutput'
$result = Invoke-CapturedProcess (Join-Path $env:SystemRoot 'System32\msiexec.exe') '/a "C:\AutoDeployTest\packages\custom-msi\rustpm-0.1.5-x64.msi" /qn TARGETDIR="C:\RustpmInspect" /L*v "C:\AutoDeployOutput\msi-extract.log"' 180
$result.Output | Set-Content -LiteralPath (Join-Path $output 'msi-extract-output.txt') -Encoding UTF8
if ($result.Code -ne 0) { throw "Administrative extraction failed: $($result.Code)" }
foreach ($name in @('rustpm-privd.exe','rustpmd.exe','rustpmctl.exe')) {
    $file = Get-ChildItem -LiteralPath 'C:\RustpmInspect' -Recurse -Filter $name | Select-Object -First 1
    $check = Invoke-CapturedProcess $file.FullName '--help' 15
    @("ExitCode=$($check.Code)", $check.Output) | Set-Content -LiteralPath (Join-Path $output ($name + '-help.txt')) -Encoding UTF8
    & 'C:\AutoDeployPatch\Inspect-PeImports.ps1' -Path $file.FullName | Set-Content -LiteralPath (Join-Path $output ($name + '-imports.json')) -Encoding UTF8
}
Get-ChildItem -LiteralPath 'C:\RustpmInspect' -Recurse -Filter '*.conf' | ForEach-Object {
    "FILE: $($_.FullName)"
    Get-Content -LiteralPath $_.FullName
} | Set-Content -LiteralPath (Join-Path $output 'rustpm-configs.txt') -Encoding UTF8
