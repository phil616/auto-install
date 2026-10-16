$ErrorActionPreference = 'Stop'
$script:WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

function Resolve-WorkspacePath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Expected a workspace-relative path: $RelativePath"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $script:WorkspaceRoot $RelativePath))
    if (-not $full.StartsWith($script:WorkspaceRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes workspace: $RelativePath"
    }
    return $full
}

function Read-JsonFile([string]$Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-DeploymentPlan([string]$Profile, [string[]]$Only) {
    if ($Profile -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid profile name.' }
    $profileData = Read-JsonFile (Resolve-WorkspacePath "config/profiles/$Profile.json")
    if ($null -eq $profileData.plugins -or $profileData.plugins -isnot [Array]) { throw 'Profile plugins must be an array.' }
    $seen = @{}
    foreach ($id in $profileData.plugins) {
        if ($id -isnot [string] -or $id -notmatch '^[a-zA-Z0-9_-]+$' -or $seen.ContainsKey($id)) { throw "Invalid/duplicate plugin: $id" }
        $seen[$id] = $true
    }
    foreach ($id in $Only) { if (-not $seen.ContainsKey($id)) { throw "Plugin '$id' is not in profile '$Profile'." } }
    foreach ($id in $profileData.plugins) {
        if ($Only.Count -gt 0 -and $Only -notcontains $id) { continue }
        $plugin = Read-JsonFile (Resolve-WorkspacePath "config/plugins/$id.json")
        foreach ($field in @('id','version','module','package','sha256','architecture','requiresAdmin','timeoutSeconds','arguments','targetDir','skipIfVerified','verify')) {
            if ($null -eq $plugin.PSObject.Properties[$field]) { throw "Plugin $id missing field: $field" }
        }
        if ($plugin.id -cne $id) { throw "Plugin ID mismatch: $id" }
        if ($plugin.architecture -notin @('x64','x86','any')) { throw "Invalid architecture: $id" }
        if ($plugin.requiresAdmin -isnot [bool] -or $plugin.skipIfVerified -isnot [bool]) { throw "Boolean fields must be JSON booleans: $id" }
        if ($plugin.timeoutSeconds -isnot [ValueType] -or $plugin.timeoutSeconds -lt 1 -or $plugin.timeoutSeconds -gt 86400 -or $plugin.timeoutSeconds % 1 -ne 0) { throw "Invalid timeout (1..86400 seconds): $id" }
        $modulePath = Resolve-WorkspacePath $plugin.module
        $packagePath = Resolve-WorkspacePath $plugin.package
        if (-not $modulePath.StartsWith((Resolve-WorkspacePath 'scripts') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Plugin modules and dependencies must be under scripts/: $id" }
        if ([IO.Path]::GetExtension($modulePath) -ine '.au3' -or -not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Missing AutoIt module: $modulePath" }
        $issues = [Collections.Generic.List[string]]::new()
        if ([string]::IsNullOrWhiteSpace($plugin.version) -or $plugin.version -match 'TODO') { $issues.Add('version is not set') }
        if ($plugin.sha256 -notmatch '^[a-fA-F0-9]{64}$') { $issues.Add('SHA256 is not set') }
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { $issues.Add('package is missing') }
        foreach ($field in @('path','arguments','contains')) {
            if ($null -eq $plugin.verify.PSObject.Properties[$field]) { throw "Plugin $id missing verify.$field" }
        }
        if ([string]::IsNullOrWhiteSpace($plugin.verify.path) -or $plugin.verify.path -match 'TODO' -or $plugin.verify.contains -match 'TODO') { $issues.Add('verification is not configured') }
        if ($plugin.skipIfVerified -and [string]::IsNullOrWhiteSpace($plugin.verify.contains)) { $issues.Add('skipIfVerified requires a version-specific verify.contains') }
        [pscustomobject]@{ Id = $id; Plugin = $plugin; ModulePath = $modulePath; PackagePath = $packagePath; Issues = $issues }
    }
}

function Assert-DeploymentReady([object[]]$Plan) {
    $failures = [Collections.Generic.List[string]]::new()
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    foreach ($item in $Plan) {
        foreach ($issue in $item.Issues) { $failures.Add("$($item.Id): $issue") }
        if ($item.Plugin.architecture -eq 'x64' -and $nativeArchitecture -ne 'AMD64') { $failures.Add("$($item.Id): requires an AMD64 Windows target") }
        if ((Test-Path -LiteralPath $item.PackagePath -PathType Leaf) -and $item.Plugin.sha256 -match '^[a-fA-F0-9]{64}$') {
            if ((Get-FileHash -LiteralPath $item.PackagePath -Algorithm SHA256).Hash -ine $item.Plugin.sha256) { $failures.Add("$($item.Id): SHA256 mismatch") }
        }
    }
    if ($failures.Count -gt 0) { throw ("Preflight failed; no installer was started:`n" + ($failures -join "`n")) }
}

function Invoke-CapturedProcess([string]$File, [string]$Arguments, [int]$TimeoutSeconds, [hashtable]$Environment = @{}) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $File
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $script:WorkspaceRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) { $start.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill() # Stop this worker only; do not kill an installer/process tree.
            return [pscustomobject]@{ Code = 124; Output = 'Worker timeout. An installer may still be running; inspect before retrying.' }
        }
        $process.WaitForExit()
        # A detached child may inherit stdout; do not block forever waiting for its pipe.
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            return [pscustomobject]@{ Code = 124; Output = 'Output pipe remained open. An installer may still be running; inspect before retrying.' }
        }
        return [pscustomobject]@{ Code = $process.ExitCode; Output = $stdout.Result + $stderr.Result }
    } finally { $process.Dispose() }
}

function Test-PluginInstalled($Plugin) {
    $path = [Environment]::ExpandEnvironmentVariables($Plugin.verify.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    if ([string]::IsNullOrWhiteSpace($Plugin.verify.arguments)) { return $true }
    $arguments = ([Environment]::ExpandEnvironmentVariables($Plugin.verify.arguments)).Replace('{root}', $script:WorkspaceRoot)
    $check = Invoke-CapturedProcess $path $arguments 30
    return ($check.Code -eq 0 -and $check.Output.Contains([string]$Plugin.verify.contains))
}

function Get-AutoItPath {
    return (Resolve-WorkspacePath 'tools/autoit/install/AutoIt3.exe')
}

function Assert-AutoIt {
    $runtime = Get-AutoItPath
    if (-not (Test-Path -LiteralPath $runtime)) { throw 'Run scripts/Bootstrap.ps1 first.' }
    $version = (Get-Item -LiteralPath $runtime).VersionInfo
    if ($version.FileMajorPart -ne 3 -or $version.FileMinorPart -ne 3 -or $version.FileBuildPart -ne 18 -or $version.FilePrivatePart -ne 0) { throw 'Expected AutoIt 3.3.18.0.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $runtime
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'AUTOIT CONSULTING LTD') { throw 'AutoIt signature validation failed.' }
}
