[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    $registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    try {
        $key = $registry.OpenSubKey('SOFTWARE\rustpm')
        if ($null -eq $key) { throw 'Missing rustpm installation registration.' }
        try {
            if ($key.GetValue('Version') -ne '0.1.5') { throw 'Expected rustpm 0.1.5.' }
            $installDir = [string]$key.GetValue('InstallPath')
        } finally { $key.Dispose() }
        $product = $registry.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{E004489E-69C7-4FC3-B9E9-F9FC7F230934}')
        if ($null -eq $product) { throw 'MSI ProductCode is not registered.' }
        $product.Dispose()
    } finally { $registry.Dispose() }
    if ([string]::IsNullOrWhiteSpace($installDir)) { throw 'Missing install path.' }
    foreach ($file in @('rustpmd.exe','rustpm-privd.exe','rustpmctl.exe','cli\rustpmctl.exe','config\rustpmd.conf')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installDir $file) -PathType Leaf)) { throw "Missing installed file: $file" }
    }
    foreach ($name in @('rustpm','rustpm-privd')) {
        $service = Get-Service -Name $name -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(8))
    }
    Write-Output 'rustpm 0.1.5 verified: MSI registration, installed files, both services running.'
    exit 0
} catch { Write-Output $_.Exception.Message; exit 1 }
