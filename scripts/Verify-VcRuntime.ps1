[CmdletBinding()]
param([version]$MinimumVersion = '14.51.36247.0')
$ErrorActionPreference = 'Stop'
try {
    $found = $false
    foreach ($view in @('Registry64','Registry32')) {
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        try {
            $key = $root.OpenSubKey('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64')
            if ($null -eq $key) { continue }
            try {
                $versionText = ([string]$key.GetValue('Version')).TrimStart('v')
                if ($key.GetValue('Installed') -eq 1 -and [version]$versionText -ge $MinimumVersion) { $found = $true }
            } finally { $key.Dispose() }
        } finally { $root.Dispose() }
    }
    if (-not $found) { throw "VC++ x64 runtime $MinimumVersion or later is required." }
    $nativeDirectory = if ([Environment]::Is64BitProcess) { 'System32' } else { 'Sysnative' }
    if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot "$nativeDirectory\vcruntime140.dll"))) { throw 'Missing x64 VCRUNTIME140.dll.' }
    Write-Output "VC Runtime x64 >= $MinimumVersion verified"
    exit 0
} catch { Write-Output $_.Exception.Message; exit 1 }
