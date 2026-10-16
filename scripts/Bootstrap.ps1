[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Workspace.ps1')
$lockData = Read-JsonFile (Resolve-WorkspacePath 'tools/autoit.lock.json')
$archive = Resolve-WorkspacePath 'tools/autoit-v3.zip'
$runtime = Get-AutoItPath
if (Test-Path -LiteralPath $runtime) {
    Assert-AutoIt
    Write-Host 'AutoIt 3.3.18.0 is ready.'
    exit 0
}
if (-not (Test-Path -LiteralPath $archive)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $lockData.url -OutFile $archive -UseBasicParsing
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $lockData.sha256) { throw 'AutoIt archive hash mismatch. Check the download before replacing the lock file.' }
Expand-Archive -LiteralPath $archive -DestinationPath (Resolve-WorkspacePath 'tools/autoit') -Force
Assert-AutoIt
Write-Host 'AutoIt 3.3.18.0 is ready. No registry or system PATH changes were made.'
