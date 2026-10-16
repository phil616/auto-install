# Windows 软件自动安装工作区

基于 AutoIt v3 的可插拔安装方案。首批包含 **Git、uv、用户提供的 MSI**。每个软件独立配置，方案清单只负责选哪些插件、按什么顺序安装；不同交付包可以组合不同的软件。

当前已准备 AutoIt **3.3.18.0 官方便携版**、执行器、插件模板、校验与打包工具。已接入固定版本 **Git 2.56.0.windows.2、uv 0.13.1、rustpm MSI 0.1.5**，并锁定安装包 SHA256。Git/uv 使用官方发布文件，MSI 来自用户提供的根目录文件，原件保留。沙盒测试发现 MSI 依赖 **VC++ x64 运行库**，已作为独立插件纳入方案并固定为 **14.51.36247.0**。

本机已安装这些软件，真实安装验收使用 Windows Sandbox；不要在宿主机运行下面示例中的 `-Execute`。测试结果见 [首批接入进度](docs/software-plan.md)。

## 按任务阅读

| 任务 | 文档 |
| --- | --- |
| 给目标电脑安装 | [安装使用说明](docs/usage.md) |
| 智能体接手、制作插件与新方案 | [智能体操作手册](docs/agent-playbook.md) |
| 具体测试步骤、断言与排障 | [测试方案](docs/test-plan.md) |
| 构建候选、附验收证据、校验和交付 | [构建与发布](docs/build-release.md) |

当前自动 Sandbox 测试固定 dev 四项；新方案需先适配 Guest 测试逻辑。Build 不自动携带测试报告，具体归档步骤已在构建文档中列出。

## 快速开始

在工作区 PowerShell 中执行，命令兼容 Windows PowerShell 5.1 与 PowerShell 7：

```powershell
# 本机工具已准备；新工作区可用此命令恢复工具
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Bootstrap.ps1

# 按锁文件恢复官方 Git/uv/VC++ 安装包，不安装软件
.\scripts\Download-Packages.ps1

# 默认只显示计划，不启动安装器
.\Start.ps1
.\Start.ps1 -Profile dev -Only git

# 语法、配置及工具链检查（不要求业务安装包已就绪）
.\scripts\Check.ps1
.\tests\Smoke.ps1
```

`-ExecutionPolicy Bypass` 只作用于该次 PowerShell 进程，不修改系统执行策略。若组织策略禁止运行脚本，使用组织批准的脚本签名/执行方式。

在预检、测试和交付阶段：

```powershell
# 完整预检：缺包、缺版本、未设验证或摘要不符时直接失败
.\Start.ps1 -Profile dev -Validate

# 测试机上逐个验证；需要管理员权限的插件请从管理员 PowerShell 执行
.\Start.ps1 -Profile dev -Only git -Execute
.\Start.ps1 -Profile dev -Only uv -Execute
.\Start.ps1 -Profile dev -Only vc-runtime-x64 -Execute
.\Start.ps1 -Profile dev -Only custom-msi -Execute

# 全部就绪后顺序安装，或构建携带安装包和运行时的离线 ZIP
.\Start.ps1 -Profile dev -Execute
.\scripts\Build.ps1 -Profile dev
```

隔离安装验收入口（先构建，BundlePath 指向构建输出目录）：

```powershell
.\scripts\Test-Sandbox.ps1 -BundlePath .\artifacts\dev-<构建标识> -MsiCompatibilityWorkaround
```

该入口映射安装源为只读，在沙盒内复制并逐项安装，仅将报告和日志写回指定输出目录。已有沙盒时会拒绝启动，先保留其数据并明确决定是否关闭。详见 [沙盒验收](docs/sandbox.md)。

`-MsiCompatibilityWorkaround` 只在本次沙盒中关闭导致 MSI 检查缓慢的信誉策略并刷新 CI；不影响宿主机，正式安装入口也不会改此策略。不需要该兼容设置时可省略。

## 工作区

| 路径 | 用途 |
| --- | --- |
| `config/plugins/` | 软件版本、安装包摘要、安装模块、参数和验证条件 |
| `config/profiles/` | 不同交付方案的插件列表；数组顺序即安装顺序 |
| `scripts/modules/` | AutoIt 安装插件：EXE、MSI、uv，及后续自定义模块 |
| `scripts/lib/` | 共用执行与进程等待逻辑 |
| `templates/` | 新插件配置、窗口自动化模板 |
| `packages/` | 本地离线安装包，不进入版本控制 |
| `tools/` | 固定版本的 AutoIt 工具链与下载锁定文件 |
| `logs/` | 每次运行的分项日志及 `results.json` |
| `artifacts/` | 按方案构建的目录、ZIP 和文件摘要清单 |
| `tests/` | 无真实软件安装的执行链冒烟测试 |

详细步骤见 [环境说明](docs/environment.md)、[插件接入规范](docs/plugins.md)、[部署与交付](docs/deployment.md)、[首批接入进度](docs/software-plan.md)。
