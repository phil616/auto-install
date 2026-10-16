[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'WDAGUtilityAccount' -or -not (Test-Path -LiteralPath 'C:\AutoDeployInput\Start.ps1')) {
    throw 'This workaround is restricted to the disposable test Sandbox.'
}
$policyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
$before = (Get-ItemProperty -LiteralPath $policyPath -Name VerifiedAndReputablePolicyState -ErrorAction Stop).VerifiedAndReputablePolicyState
Set-ItemProperty -LiteralPath $policyPath -Name VerifiedAndReputablePolicyState -Value 0
$refreshOutput = & (Join-Path $env:SystemRoot 'System32\CiTool.exe') --refresh 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Sandbox CI refresh failed: $refreshOutput" }
[pscustomobject]@{
    scope = 'disposable Windows Sandbox only'
    before = $before
    after = (Get-ItemProperty -LiteralPath $policyPath -Name VerifiedAndReputablePolicyState).VerifiedAndReputablePolicyState
    refresh = $refreshOutput.Trim()
    issue = 'https://github.com/microsoft/Windows-Sandbox/issues/68'
}
