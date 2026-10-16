[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$LogDir
)
$ErrorActionPreference = 'Stop'
try {
    $stage = Join-Path $LogDir ('uv-stage-' + [guid]::NewGuid().ToString('N'))
    # Sandbox images can omit Archive module language resources. Use .NET ZIP APIs.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $stage)
    $uv = @(Get-ChildItem -LiteralPath $stage -Filter uv.exe -Recurse)
    $uvx = @(Get-ChildItem -LiteralPath $stage -Filter uvx.exe -Recurse)
    if ($uv.Count -ne 1 -or $uvx.Count -ne 1) { throw 'Expected exactly one uv.exe and uvx.exe in the archive.' }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $uv[0].FullName -Destination (Join-Path $Destination 'uv.exe') -Force
    Copy-Item -LiteralPath $uvx[0].FullName -Destination (Join-Path $Destination 'uvx.exe') -Force
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if (@($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $Destination.TrimEnd('\') }).Count -eq 0) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $Destination) -join ';'), 'User')
    }
    'Installed uv and uvx. Open a new terminal to load the updated user PATH.' | Set-Content -LiteralPath (Join-Path $LogDir 'uv-install.log') -Encoding UTF8
    exit 0
} catch {
    @(
        "Is64BitProcess=$([Environment]::Is64BitProcess); PSHOME=$PSHOME"
        "PSModulePath=$env:PSModulePath"
        ($_ | Format-List * -Force | Out-String)
        ($_.Exception | Format-List * -Force | Out-String)
    ) | Set-Content -LiteralPath (Join-Path $LogDir 'uv-install.log') -Encoding UTF8
    exit 1
}
