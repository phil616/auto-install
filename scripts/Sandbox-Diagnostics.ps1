[CmdletBinding()]
param([string]$OutputPath = 'C:\AutoDeployOutput\powershell-diagnostics.txt')
$ErrorActionPreference = 'Continue'
if ($env:USERNAME -ne 'WDAGUtilityAccount') { throw 'Sandbox diagnostics only.' }
& {
    "Is64BitProcess=$([Environment]::Is64BitProcess)"
    "PSHOME=$PSHOME"
    "PSModulePath=$env:PSModulePath"
    Get-Module -ListAvailable Microsoft.PowerShell.Archive | Format-List *
    try { Import-Module Microsoft.PowerShell.Archive -Force -ErrorAction Stop; 'Archive import succeeded.' }
    catch { $_ | Format-List * -Force; $_.Exception | Format-List * -Force; $_.Exception.InnerException | Format-List * -Force }
    Get-Process -Name msiexec,AutoIt3,rustpmd,rustpm-privd -ErrorAction SilentlyContinue | Select-Object Name,Id,CPU,StartTime | Format-Table
    Get-Service -Name msiserver,rustpm,rustpm-privd -ErrorAction SilentlyContinue | Format-Table
    Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller'} -MaxEvents 6 -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message | Format-List
    Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Service Control Manager'} -MaxEvents 10 -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message | Format-List
    Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1001} -MaxEvents 6 -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message | Format-List
} | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Width 240
