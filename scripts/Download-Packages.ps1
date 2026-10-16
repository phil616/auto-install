[CmdletBinding()]
param([ValidateSet('git','uv','vc-runtime-x64')][string[]]$Only = @('git','uv','vc-runtime-x64'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Workspace.ps1')
$lockData = Read-JsonFile (Resolve-WorkspacePath 'tools/packages.lock.json')
foreach ($item in $lockData.packages) {
    if ($Only -notcontains $item.id) { continue }
    $destination = Resolve-WorkspacePath $item.package
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $destination) {
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $item.sha256) { throw "Existing package hash mismatch: $destination" }
    } else {
        if (([uri]$item.url).Scheme -ne 'https' -or ([uri]$item.url).Host -notin @('github.com','download.visualstudio.microsoft.com')) { throw 'Expected a pinned official HTTPS release URL.' }
        $partial = $destination + '.partial'
        & curl.exe --fail --location --retry 2 --silent --show-error --output $partial $item.url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $($item.id)" }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ine $item.sha256) { throw "Downloaded package hash mismatch: $($item.id)" }
        Move-Item -LiteralPath $partial -Destination $destination
    }
    if ($item.signatureSubjectContains) {
        $signature = Get-AuthenticodeSignature -LiteralPath $destination
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate.Subject.Contains($item.signatureSubjectContains)) { throw "Publisher signature validation failed: $($item.id)" }
    }
    Write-Host "$($item.id) $($item.version): official release SHA256 verified."
}
