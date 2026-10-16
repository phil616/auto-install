# 首批软件接入进度

| 插件 | 方案 | 版本与来源 | 验证方式 |
| --- | --- | --- | --- |
| Git | `dev` 第 1 项 | 2.56.0.windows.2，[官方 release](https://github.com/git-for-windows/git/releases/tag/v2.56.0.windows.2) | 安装器签名、官方 SHA256、确切版本及 PATH |
| uv | `dev` 第 2 项 | 0.13.1，[官方 release](https://github.com/astral-sh/uv/releases/tag/0.13.1) | 官方 SHA256、uv/uvx、用户 PATH、确切版本 |
| VC++ x64 运行库 | `dev` 第 3 项 | 14.51.36247.0，微软官方签名文件 | 版本注册、x64 DLL，支持已安装新版时跳过 |
| 自定义 MSI（rustpm） | `dev` 第 4 项 | 0.1.5，用户提供 `rustpm-0.1.5-x64.msi` | 文件 SHA256、MSI 产品/版本注册、已安装文件、双服务运行、CLI |

四个安装包已就绪，配置已补齐。宿主机已有业务软件，本次未在宿主机执行真实安装。根目录 MSI 原件保留；工作副本位于 `packages/custom-msi/`。最终封装格式仍可扩展，当前交付便携目录与 ZIP。

Git/uv 版本与官方发布摘要锁定在 `tools/packages.lock.json`，恢复下载命令为 `scripts/Download-Packages.ps1`。MSI 静态检查证据在 `logs/rustpm-msi-inspection.json`，包含 ProductCode、目录、文件及注册表信息。

## 工作区初始化验证

- AutoIt 官方便携包已下载，版本为 3.3.18.0，解释器数字签名验证通过。
- 自动检查入口：`scripts/Check.ps1`。
- 行为验证入口：`tests/Smoke.ps1`，用无害临时模块覆盖预演、预检、顺序执行、摘要错误时整体阻止、失败停止、验证失败停止、重启停止及超时停止。
- 打包验证：`scripts/Build.ps1 -Profile empty`，不包含真实安装器。

初始化已通过 8 项执行链冒烟场景。测试使用 Windows PowerShell 5.1 和实际 AutoIt 解释器，包含带中文和空格的文件路径、超过 260 字符的进程命令行及快速进程退出码。业务安装效果仍需在实际目标系统上逐项验收。

真实安装测试由 [沙盒验收入口](sandbox.md) 执行。沙盒确认初始 Git、uv、rustpm 均不存在后才开始；报告和实际安装日志保存在 `logs/sandbox-<标识>/output/`。后续新增其他软件遵循同一插件接口。

已在沙盒单项验证四个插件。调试中定位并修复了 uv 解压对缺失 Archive 语言资源的依赖；rustpm MSI 的服务启动失败由缺少 VC++ 运行库引起，补齐后安装及双服务验证成功。完整方案回归结果以各次 `sandbox-report.json` 为准。

## 2026-10-16 完整回归通过

最终使用全新沙盒，初始 Git、uv、rustpm 均不存在。Git → uv → VC++ x64 运行库 → rustpm MSI 四项退出码全部为 0，Git/uv/uvx 版本与 PATH、rustpmctl CLI 及双服务运行验证均通过。报告状态为 `passed`。

使用了 `-MsiCompatibilityWorkaround`，只在临时沙盒中将信誉策略从 2 改为 0 并刷新 CI；该条件记录在报告中。本次测试网络开启，不代表断网或其他 Windows 版本已验收。

工作区证据目录：`logs/sandbox-20261016-225651-91245eb8/output/`。正式 ZIP 的 `validation/` 同时附带报告、CLI 输出和服务状态。宿主机未执行真实软件安装或修改 CI 策略，测试沙盒在日志导出后关闭。
