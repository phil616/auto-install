# 智能体操作手册：制作、测试与交付

本手册面向接手工作区的智能体。目标是把软件接为独立 AutoIt 插件，用方案清单组合，在隔离 Windows 中验证，再交付可直接运行的目录或 ZIP。

先读根目录 [AGENTS.md](../AGENTS.md)。完整测试步骤见 [测试方案](test-plan.md)，构建归档见 [构建与发布](build-release.md)，目标电脑的操作见 [安装使用说明](usage.md)。本手册描述仓库现有实现，不假定脚本已有尚未实现的能力。

## 1. 已验证的结构

```text
Start.ps1                 PowerShell 编排：预检 → 顺序调起 AutoIt → 安装后验证
config/plugins/<id>.json  单个软件的包、版本、摘要、模块与验证条件
config/profiles/<名>.json 插件数组；数组顺序就是执行顺序
scripts/modules/*.au3     AutoIt 安装模块
scripts/lib/Common.au3    原生进程启动、有限等待、退出码和系统工具路径
scripts/Verify-*.ps1      只读验证，不能在验证中安装或修复
packages/<id>/           离线包，忽略版本控制
tools/*.lock.json         AutoIt 与官方下载版本/摘要记录
logs/                    安装、冒烟和 Sandbox 证据
artifacts/               每次构建的新目录及 ZIP
```

当前 `dev` 顺序是 `git → uv → vc-runtime-x64 → custom-msi`。MSI 为用户提供的 rustpm 0.1.5；VC++ 是在干净沙盒里实际发现的前置依赖。四项曾在同一全新沙盒中通过验收，见 [已完成记录](software-plan.md)。

## 2. 接手时先做什么

1. 查看用户要求和现有文件，保留用户安装包原件，不从文件名猜测全部安装行为。
2. 阅读目标插件、方案、安装模块和验证脚本；确认安装范围、依赖、目标架构、版本和期望产物。
3. 在英文工作区路径下工作，允许空格；`.ps1` / `.au3` 保存 UTF-8 BOM，以兼容 Windows PowerShell 5.1。Au3Check 对中文工作区 include 路径有已发现的限制。
4. 工具缺失时运行 `scripts/Bootstrap.ps1`，业务包缺失时运行 `scripts/Download-Packages.ps1`。下载器当前只接受 Git、uv、vc-runtime-x64 三个 ID；新增软件需要扩展锁文件及下载器的 ID/域名约束，或另用可审查的固定下载步骤。
5. 本机已安装业务软件，禁止在宿主机执行真实 `-Execute`。宿主机可进行下载、静态检查、预演、预检、无害冒烟测试和构建。

## 3. 如何制作插件

### 收集安装依据

- 下载官方固定版本的完整离线包，记录原始 URL、SHA256、架构和可用的数字签名。可变的 `latest` 链接需要解析到固定文件，不能在每次部署时自动升级。
- 对用户提供的 MSI，使用只读数据库检查识别产品、版本、目录、文件、注册与服务。不要在宿主机通过运行 MSI 来“看看效果”。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Inspect-Msi.ps1 `
  -Path .\rustpm-0.1.5-x64.msi
Get-FileHash .\packages\custom-msi\rustpm-0.1.5-x64.msi -Algorithm SHA256
```

`Inspect-Msi.ps1` 当前读取固定表集合，其他 MSI 若缺少其中某张表可能失败；应按实际数据库表调整查询，而不是启动安装器代替静态检查。

### 配置并复用模块

1. 复制 `templates/plugin.json` 为 `config/plugins/<id>.json`，修改 ID，填写实际版本和安装包摘要，去除 TODO。
2. 根据安装器选择模块：

| 类型 | 模块与要求 |
| --- | --- |
| 带静默参数的 EXE | `scripts/modules/exe.au3`；按厂商资料填写参数，不能假定统一 `/S` |
| MSI | `scripts/modules/msi.au3`；已添加静默、禁止自动重启及详细日志，额外参数只填产品属性等 |
| uv 官方 ZIP | `scripts/modules/uv.au3`；通过辅助脚本部署 uv/uvx 和用户 PATH |
| 特殊安装/其他产物 | 自建 `scripts/modules/<id>.au3`，复用 Common.au3 |
| 必须操作安装窗口 | 复制 `templates/gui.au3` 到模块目录，用 Au3Info 采集实际窗口与控件，再逐页实现 |

3. 设置 `requiresAdmin`、架构、有限超时、安装目标和只读验证。完整字段见 [插件接口](plugins.md)。
4. CLI 软件使用绝对路径及版本输出验证；服务型软件应同时验证产品注册、必要文件和服务状态。不能只凭安装器返回 0 宣称成功。
5. 如需辅助验证脚本，放在 `scripts/` 中，用 `verify.arguments` 的 `{root}` 指向交付包。脚本用非零退出码报告失败，成功输出明确的验证字符串。
6. 依赖作为独立插件加入方案，并排在使用者之前。执行器不会自动推导依赖，`-Only` 也不会自动补齐依赖。

### 自定义模块约定

Common.au3 提供 `_RequiredEnv`、`_Quote`、`_Exec`、`_Start`、`_Wait` 和 `_NativeSystemDir`。环境变量及退出码定义见 [模块接口](plugins.md)。

- 所有等待有限时；保留安装器退出码，失败后不继续点击或自动重试。
- 控件操作用明确窗口/页面文本和控件标识。不要把坐标或连点“下一步”作为通用安装方案。
- 默认 32 位 AutoIt 在 x64 Windows 上应通过 `_NativeSystemDir()` 调用原生 PowerShell/msiexec；不要忽略 WOW64 重定向。
- EXE 安装器可能派生子进程后提前退出。模块必须确认真正完成，安装后验证不能检查到旧文件就误判成功。
- 当前每插件只有一个主安装包。多个文件可封装为单个 ZIP，摘要覆盖整个 ZIP；依赖及辅助脚本必须一起交付，不能引用开发机私有绝对路径。

## 4. 如何组合不同产物

例如仅部署 Git 与 uv，新建 `config/profiles/python-dev.json`：

```json
{
  "name": "python-dev",
  "plugins": ["git", "uv"]
}
```

使用 `Start.ps1 -Profile python-dev` 预演，`Build.ps1 -Profile python-dev` 构建。相同软件的不同版本/参数可使用不同插件 ID，共用模块。当前构建器输出目录和 ZIP；其他封装格式应另加构建步骤，保留插件接口。

**当前 Sandbox 自动测试不是通用方案执行器。** `Sandbox-Guest.ps1` 固定 `dev`、四个 ID、三项初始检测以及四条 CLI 检查。`Test-Sandbox.ps1` 没有 `-Profile` 参数。新方案不能直接套用该入口就宣称通过；必须先按 [自定义方案测试要求](test-plan.md#自定义方案如何适配测试) 修改/扩展测试，再验证选中的真实产物。

## 5. 必须遵守的闭环

```text
收集来源/依赖 → 配置插件与清单 → 静态检查和冒烟 → 全量预检
→ 构建候选目录 → 全新 Sandbox 验收 → 审查报告与实际日志
→ 在同一个候选目录附加证据 → 重建摘要清单 → 压缩及校验 ZIP → 交付使用说明
```

执行命令和通过标准分别在 [测试方案](test-plan.md) 与 [构建与发布](build-release.md)。

修改包、安装参数、模块、验证逻辑、依赖顺序后，旧验收不能沿用：产生新候选并重新测试。只修改文档时核对内容与链接，无需再次安装业务软件。

沙盒有现有用户会话时先保留；关闭会丢失数据，只有用户明确授权才能结束。自己的测试会话结束前先导出日志，再按记录的会话 ID 关闭。不要根据进程名终止所有 Sandbox 或 msiexec。

## 6. 交接给下一位智能体时写清楚

- 方案名、插件顺序、版本、包来源/摘要，哪些依赖不可省略。
- 实际通过的静态/冒烟/安装测试，报告路径和对应候选目录。
- 是否开启网络、是否启用沙盒 CI 兼容开关、使用什么账户；不能把有条件通过说成所有系统都通过。
- 交付 ZIP 路径、ZIP SHA256 和目标机启动命令。
- 尚未覆盖的系统、升级/重启/断网/不同用户等场景，及任何当前限制。
- 明确宿主机是否发生真实安装或策略修改；本工作区要求两者都不发生。
