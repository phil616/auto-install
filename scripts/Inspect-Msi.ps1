[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
$fullPath = (Resolve-Path -LiteralPath $Path).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($fullPath, 0))
$tables = [ordered]@{}
try {
    foreach ($table in @('Property','Directory','File','Component','Registry','Environment','CustomAction')) {
        $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database, @('SELECT * FROM `' + $table + '`'))
        $rows = @()
        try {
            [void]$view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
            while ($record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)) {
                $count = $record.GetType().InvokeMember('FieldCount', 'GetProperty', $null, $record, $null)
                $fields = @(for ($i = 1; $i -le $count; $i++) { $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @($i)) })
                $rows += ,$fields
                [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
            }
        } finally {
            [void]$view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
        }
        $tables[$table] = $rows
    }
    [pscustomobject]@{ path = $fullPath; sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash; tables = $tables } | ConvertTo-Json -Depth 8
} finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
