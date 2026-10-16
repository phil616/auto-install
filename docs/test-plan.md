# 具体测试方案与验收标准

本方案区分工具链、执行链和真实安装。通过一类检查不能替代另一类。宿主机只运行无真实安装的检查；真实安装只能在用户授权的测试机或隔离 Windows 中运行。

## 测试层次

| 层次 | 入口 | 证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| 静态检查 | `scripts/Check.ps1` | PS 语法、配置/方案结构、AutoIt 模块语法、运行时可用 | 软件安装、包下载齐全或业务功能 |
| 执行链冒烟 | `tests/Smoke.ps1` | 无害临时模块下的预演、预检、顺序、退出码、停止行为 | 真实安装器行为和实际重启 |
| 包与环境预检 | `Start.ps1 -Profile dev -Validate` | 全部所选插件配置齐全、包摘要匹配、运行时和架构满足 | 已安装软件正确、真实安装一定成功 |
| 干净安装验收 | `scripts/Test-Sandbox.ps1` | 当前 dev 四项在全新 Sandbox 中安装并验证 | 所有 Windows 版本、所有用户、完全断网和升级场景 |
| 交付检查 | [构建与发布](build-release.md) | 同一候选的打包完整性、摘要及证据一致 | 新增业务兼容性 |

Check 和 Smoke 不要并行：Smoke 会临时创建/删除方案、插件和 AutoIt 文件。脚本检查与安装测试都要保留真实结果，不能只截取“命令已启动”的输出。

## A. 宿主机的无害检查

在工作区根目录运行，每步失败先处理，不继续下一步：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check.ps1
if ($LASTEXITCODE -ne 0) { throw '静态检查失败' }

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke.ps1
if ($LASTEXITCODE -ne 0) { throw '冒烟失败' }

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start.ps1 -Profile dev -Validate
if ($LASTEXITCODE -ne 0) { throw '安装包预检失败' }
```

Check 预期输出 `PowerShell syntax, JSON/profiles and AutoIt modules passed`；Smoke 预期为 `8 smoke scenarios passed`；预检预期为 `Preflight passed. No installer started.`，三者退出码均为 0。

### 现有 8 项自动冒烟

| 编号 | 构造与动作 | 预期退出码 | 核心断言 |
| --- | --- | --- | --- |
| M01 | 默认预演临时方案 | 0 | 没有创建安装标记 |
| M02 | 对同一无害方案运行 Validate | 0 | 只做预检 |
| M03 | 两个成功临时插件顺序 Execute | 0 | 两个标记都产生，代码被实际执行 |
| M04 | 第二个插件摘要被设为错误值 | 1 | 全量预检阻止第一个插件启动 |
| M05 | 第一个插件返回 1 | 1 | 第二个插件不执行 |
| M06 | 首项返回 0 但不产生验证文件 | 1 | 验证失败使队列停止 |
| M07 | 首项返回 3010 | 3010 | 记录重启请求并停止后项 |
| M08 | 无害等待进程超过模块限时 | 124 | 超时停止后项 |

临时模块还覆盖中文/空格文件路径、超过 260 字符的进程命令行和快速进程退出码。测试在 `finally` 清理自己的临时配置/模块，证据保留在 `logs/smoke-*` 和对应运行日志。M07 只模拟退出码，没有实际重启机器。

## B. 构建并固定候选

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -Profile dev -SkipArchive
if ($LASTEXITCODE -ne 0) { throw '候选构建失败' }
```

从输出 `Folder:` 复制确切路径，后续始终使用这一目录。不要用“最新目录”自动替换测试对象，尤其是多个智能体或多个构建同时存在时。

```powershell
# 替换为本次实际输出，以下占位符不可直接执行
$bundlePath = 'D:\Data\userautodeploy\artifacts\dev-<本次构建标识>'
```

## C. 启动全新 Sandbox

先检查 `Get-Command wsb.exe` 和 `wsb.exe list --raw`。如果系统未启用 Sandbox，先按 [Microsoft 安装说明](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-install) 准备虚拟化环境；若涉及系统功能启用或重启，报告实际状态，不自行重启宿主机。

若有现有会话，不自动停止。用户明确授权关闭后，只关闭确认的会话 ID；不能沿用已经安装软件的旧环境作为最终干净安装证据。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Sandbox.ps1 `
  -BundlePath $bundlePath -MsiCompatibilityWorkaround
if ($LASTEXITCODE -ne 0) { throw '沙盒启动失败' }
```

`-MsiCompatibilityWorkaround` 是当前镜像验证使用的条件，其他镜像不需要时可省略。具体 [CI 兼容条件](sandbox.md#本机-sandbox-的兼容条件) 必须写进验收结论。

入口会保存 `Test.wsb`、`session.json`，打印报告位置并返回。**入口退出 0 只说明已启动，安装仍可能在后台运行。**

映射关系如下，不能把整个工作区映射为可写安装目录：

| 主机内容 | 沙盒路径 | 权限/用途 |
| --- | --- | --- |
| 本次候选目录 | `C:\AutoDeployInput` | 只读安装源 |
| 本次 output 目录 | `C:\AutoDeployOutput` | 只写回报告和日志所需的可写目录 |
| 无主机映射 | `C:\AutoDeployTest` | 沙盒本地副本，实际安装入口 |

网络开启，剪贴板、音视频输入、打印机重定向和 vGPU 关闭。安装由沙盒账户执行；辅助脚本检查 WDAGUtilityAccount 与约定映射，拒绝宿主机执行。账户/路径检查是防误用措施，不替代 Windows Sandbox 的虚拟化隔离边界。

## D. 观察结果与判定

把打印出的本次运行目录填入变量：

```powershell
$sandboxRun = 'D:\Data\userautodeploy\logs\sandbox-<本次运行标识>'
$session = Get-Content -LiteralPath (Join-Path $sandboxRun 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$reportPath = Join-Path $session.output 'sandbox-report.json'
Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
```

启动期间报告可能暂未创建；写入期间可能短暂读到不完整 JSON，应稍后重读。`running` 不是成功；若长时间不更新，结合安装超时和当前日志检查，不能无限等待或盲目启动第二次安装。

结束后检查：

```powershell
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$expected = @('git','uv','vc-runtime-x64','custom-msi')
if ($report.status -ne 'passed' -or -not $report.finishedAt) { throw '未完成成功验收' }
if ($report.steps.Count -ne $expected.Count) { throw '插件数量不符' }
if (($report.steps.id -join ',') -ne ($expected -join ',')) { throw '插件顺序不符' }
if (@($report.steps | Where-Object { $_.exitCode -ne 0 }).Count) { throw '存在失败步骤' }
if ($report.baseline.git -or $report.baseline.uv -or $report.baseline.rustpm) { throw '起始环境不干净' }
if ($session.bundle -ne (Resolve-Path -LiteralPath $bundlePath).Path) { throw '报告不属于该候选' }
```

还需审查以下证据，不能只依赖最外层 `passed`：

| 编号 | 测试内容 | 通过标准与证据 |
| --- | --- | --- |
| S01 | 初始状态 | `baseline` 三项 false；这检测指定 Git/uv 文件与 rustpm 服务，并非全盘软件清查 |
| S02 | Git | 模块退出 0、安装后版本验证通过，`git.exe-check.log` 中为固定版本 |
| S03 | uv | uv/uvx 部署成功，uv 版本验证通过，两份 CLI 日志均成功 |
| S04 | VC++ x64 | 安装或经验证跳过；注册版本达到配置要求，原生 x64 DLL 存在 |
| S05 | rustpm MSI | 原生安装器退出 0；ProductCode、版本、必要文件、两个服务均通过 Verify-Rustpm |
| S06 | PATH/CLI | 重载机器与用户 PATH 后启动子进程，git/uv/uvx 版本、rustpmctl 帮助退出 0 |
| S07 | 执行状态 | `deployment-logs/*/results.json` 为 `installed-verified` 或允许的 `skipped-verified` |
| S08 | 完整报告 | 四项按顺序返回 0，报告 finishedAt 存在，错误为空，条件如实记录 |

CLI 测试通过重载环境并启动子进程模拟新终端，并未覆盖退出登录或另一个真实用户。`reboot-required` 和 `pending` 不是安装验证完成。

可在关闭沙盒前附加服务证据：

```powershell
wsb.exe exec --id $session.sessionId -r ExistingLogin `
  -c 'cmd.exe /c sc.exe query rustpm > C:\AutoDeployOutput\services.txt & sc.exe query rustpm-privd >> C:\AutoDeployOutput\services.txt' --raw
Get-Content -LiteralPath (Join-Path $session.output 'services.txt')
```

两个服务都应为 `STATE : 4 RUNNING`，Win32/Service 退出码为 0。

## E. 日志、调试和已遇到的问题

| 现象 | 查看什么 | 已验证的处理 |
| --- | --- | --- |
| uv 解压失败，Archive 模块加载失败 | `uv-install.log` 的内层错误，不能只看模块退出 1 | 中文 Sandbox 缺 Archive 语言资源；改用 .NET ZIP API，原生位数 PowerShell |
| MSI 开始前等待约两分钟 | `msi.log` 中软件限制策略的相邻时间戳 | Sandbox 可选 CI 兼容开关；只作用于测试 VM，记录前后值 |
| MSI 1603 / Error 1920，服务启动失败 | MSI 的 Return value 3 附近、SCM 7000/7009/7001、程序启动码 | 本次是程序缺 VCRUNTIME140.dll，退出 0xC0000135；独立加入 VC++ 前置插件后通过 |
| 表面成功但版本/服务不符 | `results.json`、Verify 脚本和 CLI 日志 | 保持失败，不删除验证或绕过错误来制造成功 |
| 超时 124 | 模块 PID、厂商日志、残留安装器 | 停止队列，先诊断；不自动重试、不按名称杀进程 |
| 3010 / 1641 | `reboot-required` 与剩余 pending 项 | 在适合重启的隔离测试机处理后验证；模拟退出码不能代表实际重启已测 |

`Sandbox-Diagnostics.ps1` 和 `Sandbox-InspectRustpm.ps1` 是本次排障辅助脚本。后者硬编码 rustpm 路径与 `C:\AutoDeployPatch`，不是通用测试入口；使用前先核对并映射实际辅助脚本目录。`Inspect-PeImports.ps1` 可只读列出原生 PE 导入 DLL。

允许在当前测试沙盒中更新脚本做定位，但这只能算调试验证。修复后必须用新候选、全新沙盒完成最终回归，不能把同一环境反复修补的结果称为从零安装通过。

## F. 结束与覆盖范围

确认报告、厂商日志、CLI 输出已导回主机，再关闭自己创建的会话：

```powershell
wsb.exe stop --id $session.sessionId --raw
```

这会丢弃沙盒内状态；只能关闭记录的本次测试 ID。超时或报告失败时，先保留诊断证据，不用重置动作掩盖失败。

当前已完成的最终回归：`logs/sandbox-20261016-225651-91245eb8/output/sandbox-report.json`。四项全部成功，CI 2→0，网络开启；测试沙盒已关闭。此历史证据只对应当次候选，后续修改不能直接继承。

下列场景应按交付需求另测，当前不得宣称已覆盖：完全断网、其他 Windows 版本/架构、业务软件升级、VC++ 已装新版时跳过、真实重启后继续、普通用户与其他管理员账户组合、真实 GUI 安装器的语言/DPI差异。测试机上验证的操作步骤可参考 [使用说明](usage.md)。

## 自定义方案如何适配测试

当前自动安装测试固定 dev。增加软件或新建方案时，至少核对：

1. Guest 脚本中的方案名、插件顺序及每项限时，和候选包配置一致。
2. 起始环境检测覆盖新增软件的确切文件、注册或服务。
3. 新增安装后验证、实际功能和 PATH/服务检查；删除不属于方案的旧 CLI 检查。
4. Host 测试入口正确传递新增参数；如果参数化方案名，不能遗漏 Guest 侧。
5. 报告的预期 ID/数量及验收断言同步更新，失败和重启仍停止后项。
6. 在全新 Sandbox 重新验收该候选。现有 Smoke 对编排的检查不能替代新增软件的真实安装测试。
