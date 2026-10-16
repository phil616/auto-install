# 构建、验收归档与交付

目标是交付已经测试的同一个候选目录，附带可核对的安装包、运行脚本、文档和摘要。下列命令在宿主机上只操作文件，不安装业务软件。

## 1. 构建前检查

确定方案名、插件顺序、固定包版本、SHA256、权限与验证条件。先按 [测试方案](test-plan.md) 通过 Check、Smoke 和该方案 Validate。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -Profile dev -SkipArchive
if ($LASTEXITCODE -ne 0) { throw '构建失败' }
```

从输出中记录本次完整目录路径：

```powershell
$bundlePath = 'D:\Data\userautodeploy\artifacts\dev-<本次构建标识>'
```

`-SkipArchive` 只生成目录。省略时同时生成 ZIP，但“构建成功”不等于“安装验收通过”。每次 Build 都创建新目录，不会自动给旧候选补 ZIP。

## 2. 当前构建器实际包含什么

| 内容 | 构建行为 |
| --- | --- |
| 安装入口 | 复制 Start.ps1，生成绑定当前方案的 Run.cmd |
| 插件/方案 | 仅复制选中方案及其插件 JSON |
| 安装包 | 仅复制所选插件的主安装包，按原相对路径放置，复制后重新校验摘要 |
| 实现和帮助 | 整个 scripts/、docs/、README.md |
| 工具链 | 完整 AutoIt install/ 与两个锁文件 |
| 日志目录 | 创建空 logs/，不复制开发机历史日志 |
| 完整性记录 | 生成 bundle-manifest.json，记录文件路径与 SHA256 |
| 验收证据 | **不会自动复制** Sandbox 报告、validation/ 或源工作区 tests/、templates/、AGENTS.md |

因此交付包可以运行安装，但不是完整的开发工作区。继续制作插件应回到源工作区；不能根据包内附带某个脚本就假定它的全部开发依赖也已复制。

自定义模块及辅助依赖放入 scripts/。每插件只有一个主安装包：多个输入文件需要封为一个受摘要覆盖的 ZIP 并配套模块，或扩展构建契约，不能只把额外文件散放在开发机上。

## 3. 测试这个候选

当前 dev 使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Sandbox.ps1 `
  -BundlePath $bundlePath -MsiCompatibilityWorkaround
```

按 [测试方案](test-plan.md) 检查最终报告、四项退出码、版本、CLI、PATH 与服务，记录本次 session.json。测试过程的启动成功不能作为验收结果。

如果需要修改安装包、参数、安装/验证脚本或方案顺序，应重新构建、重新从干净环境验收。不要测试目录 A，然后再次 Build 得到目录 B 就直接把 B 发布。

当前 Test-Sandbox/Guest 固定 dev，新方案要先适配测试。使用 empty 只验证构建结构，不能替代真实业务安装测试。

## 4. 将证据附到通过的同一候选

安装相关文件冻结后，可以添加文档与验收证据。下面的路径都要替换为本次明确记录的值，不自动挑选最新文件夹：

```powershell
$bundlePath = (Resolve-Path -LiteralPath $bundlePath).Path
$sandboxRun = 'D:\Data\userautodeploy\logs\sandbox-<本次运行标识>'
$session = Get-Content -LiteralPath (Join-Path $sandboxRun 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($session.bundle -ne $bundlePath) { throw '测试与候选不匹配' }
$reportPath = Join-Path $session.output 'sandbox-report.json'
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($report.status -ne 'passed' -or -not $report.finishedAt) { throw '不能归档未通过的报告' }
if ($report.steps.Count -ne 4 -or @($report.steps | Where-Object { $_.exitCode -ne 0 }).Count) {
    throw '当前 dev 需要四项完整成功'
}

$validationDir = Join-Path $bundlePath 'validation'
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
foreach ($name in @('sandbox-report.json','git.exe-check.log','uv.exe-check.log','uvx.exe-check.log','rustpmctl.exe-check.log')) {
    Copy-Item -LiteralPath (Join-Path $session.output $name) -Destination (Join-Path $validationDir $name)
}
# services.txt 是测试结束前可选导出的附加服务证据
$servicesPath = Join-Path $session.output 'services.txt'
if (Test-Path -LiteralPath $servicesPath) {
    Copy-Item -LiteralPath $servicesPath -Destination (Join-Path $validationDir 'services.txt')
}
```

新方案需同步修改报告 ID/数量和证据文件名，并按测试方案检查确切顺序；上述片段专用于当前 dev。完整安装器日志留在本次 output/deployment-logs，按诊断需要单独交付；不要默认把开发机全部日志、用户信息或失败调试副本塞入正式包。

## 5. 重建清单、生成最终 ZIP 与 ZIP 摘要

添加证据或更新文档后，旧清单已不足以覆盖最终文件，先重建清单。清单不包含自己，也不包含外部 ZIP：

```powershell
$manifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$manifest = @(Get-ChildItem -LiteralPath $bundlePath -Recurse -File |
    Where-Object { $_.FullName -ne $manifestPath } |
    ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName.Substring($bundlePath.Length + 1)
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
ConvertTo-Json -InputObject $manifest -Depth 4 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8

$zipPath = $bundlePath + '.zip'
Compress-Archive -Path (Join-Path $bundlePath '*') -DestinationPath $zipPath -Force
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
($zipHash + '  ' + [IO.Path]::GetFileName($zipPath)) |
    Set-Content -LiteralPath ($zipPath + '.sha256') -Encoding ASCII
```

`-Force` 只用于替换明确属于这个候选的 ZIP。完整性清单和 ZIP 摘要不等于数字签名；包来源和可用的厂商签名仍须单独验证。

## 6. 直接核对 ZIP 中的所有文件

本次交付用过以下方法，避免只验证解压前目录：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $entries = @{}
    foreach ($entry in $archive.Entries) {
        $entries[$entry.FullName.Replace('\','/')] = $entry
    }
    $reader = [IO.StreamReader]::new($entries['bundle-manifest.json'].Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }

    foreach ($item in $manifest) {
        $entry = $entries[$item.path.Replace('\','/')]
        if ($null -eq $entry) { throw "ZIP 缺少文件：$($item.path)" }
        $stream = $entry.Open()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $stream.Dispose() }
        if ($hash -ine $item.sha256) { throw "ZIP 摘要不符：$($item.path)" }
    }
    Write-Host "已核对 $($manifest.Count) 个清单文件"
} finally {
    $sha.Dispose()
    $archive.Dispose()
}
```

另将最终 ZIP 解压到新的英文、可含空格的路径，运行 `Run.cmd` 和 `Run.cmd -Validate` 检查交付入口；宿主机上这两项不能加 Execute。若安装相关文件与已测候选不同，需要重新进行隔离安装验收。

## 7. 最终交接

提供 ZIP、旁边的 `.zip.sha256`、[目标电脑使用说明](usage.md)，并指出 validation/ 报告及测试条件。已验证的安装顺序和版本不能因 README 没改就推定不变。

本次历史产物为 `artifacts/dev-20261016-225625-4ccb54ff.zip`，附带四项成功的沙盒证据；这是当次产物，不会随源文档更新。新构建要记录自己的文件名、摘要和验收报告。
