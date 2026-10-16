[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$BundlePath, [switch]$MsiCompatibilityWorkaround)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Workspace.ps1')
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'scripts/Sandbox-Guest.ps1'))) { throw 'Expected a built bundle with Sandbox-Guest.ps1.' }
$cli = (Get-Command wsb.exe -ErrorAction Stop).Source
$existing = (& $cli list --raw | Out-String | ConvertFrom-Json).WindowsSandboxEnvironments
if (@($existing).Count -gt 0) { throw 'A Sandbox session already exists. Preserve it or explicitly close it before starting a fresh test.' }
$sessionId = [guid]::NewGuid().ToString()
$runDir = Resolve-WorkspacePath ('logs/sandbox-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $sessionId.Substring(0,8))
$outputDir = Join-Path $runDir 'output'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$sourceXml = [Security.SecurityElement]::Escape($bundle)
$outputXml = [Security.SecurityElement]::Escape($outputDir)
$guestArguments = if ($MsiCompatibilityWorkaround) { ' -MsiCompatibilityWorkaround' } else { '' }
$config = @"
<Configuration>
  <Networking>Enable</Networking>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <VGpu>Disable</VGpu>
  <MappedFolders>
    <MappedFolder><HostFolder>$sourceXml</HostFolder><SandboxFolder>C:\AutoDeployInput</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\AutoDeployOutput</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\AutoDeployInput\scripts\Sandbox-Guest.ps1$guestArguments</Command></LogonCommand>
</Configuration>
"@
$config | Set-Content -LiteralPath (Join-Path $runDir 'Test.wsb') -Encoding UTF8
@{ sessionId=$sessionId; bundle=$bundle; output=$outputDir; config=(Join-Path $runDir 'Test.wsb') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'session.json') -Encoding UTF8
& $cli start --id $sessionId --config $config --raw
if ($LASTEXITCODE -ne 0) { throw "Sandbox startup failed. Configuration saved in $runDir" }
Start-Process -FilePath $cli -ArgumentList @('connect','--id',$sessionId) -WindowStyle Hidden | Out-Null
Write-Host "Sandbox session: $sessionId"
Write-Host "Report: $(Join-Path $outputDir 'sandbox-report.json')"
Write-Host 'The new test Sandbox remains running for inspection; stop only this session when done.'
