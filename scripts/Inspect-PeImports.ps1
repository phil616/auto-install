[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
function U16([int]$Offset) { [BitConverter]::ToUInt16($bytes,$Offset) }
function U32([int]$Offset) { [BitConverter]::ToUInt32($bytes,$Offset) }
if ((U16 0) -ne 0x5A4D) { throw 'Not a PE executable.' }
$pe = [int](U32 0x3c)
if ((U32 $pe) -ne 0x4550) { throw 'Invalid PE signature.' }
$optional = $pe + 24
$is64 = (U16 $optional) -eq 0x20b
$directories = $optional + $(if ($is64) {112} else {96})
$importRva = U32 ($directories + 8)
$sectionStart = $optional + (U16 ($pe+20))
$sections = @(for ($i=0; $i -lt (U16 ($pe+6)); $i++) {
    $s = $sectionStart + $i*40
    [pscustomobject]@{ rva=(U32 ($s+12)); size=[Math]::Max((U32 ($s+8)),(U32 ($s+16))); raw=(U32 ($s+20)) }
})
function OffsetOf([uint32]$Rva) {
    foreach ($section in $sections) { if ($Rva -ge $section.rva -and $Rva -lt $section.rva+$section.size) { return [int]($Rva-$section.rva+$section.raw) } }
    throw "RVA outside sections: $Rva"
}
$imports = @()
if ($importRva -ne 0) {
    $descriptor = OffsetOf $importRva
    while ((U32 ($descriptor+12)) -ne 0) {
        $nameOffset = OffsetOf (U32 ($descriptor+12))
        $end = $nameOffset
        while ($bytes[$end] -ne 0) { $end++ }
        $imports += [Text.Encoding]::ASCII.GetString($bytes,$nameOffset,$end-$nameOffset)
        $descriptor += 20
    }
}
[pscustomobject]@{ path=$Path; architecture=$(if ($is64) {'x64'} else {'x86'}); imports=$imports } | ConvertTo-Json -Depth 4
