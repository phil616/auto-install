# 插件接入规范

## 插件与方案

一个插件是一份 `config/plugins/<id>.json`，复用通用 AutoIt 模块或引用自定义 `.au3`。一个方案是一份 `config/profiles/<name>.json`。添加软件通常只增加配置和安装包；窗口安装或特殊产物再添加模块，无需修改执行器。

例如只交付 Git 与 uv，新建 `config/profiles/python-dev.json`：

```json
{
  "name": "python-dev",
  "plugins": ["git", "uv"]
}
```

`Start.ps1 -Profile python-dev` 预演，`Build.ps1 -Profile python-dev` 构建。清单数组是唯一排序依据；当前不做依赖自动推导，依赖插件需要手动列在前面。`-Only` 只从清单筛选，保留清单顺序，不会自动补齐依赖。

## 新增软件

1. 复制 `templates/plugin.json` 到 `config/plugins/<id>.json`。ID 只使用字母、数字、连字符、下划线。
2. 从官方来源或用户提供的文件准备安装包，放到 `packages/<id>/`，保留原始版本文件名也可以。
3. 填入确切 `version`、`package` 和 `Get-FileHash <包> -Algorithm SHA256` 的结果。
4. 选择 `scripts/modules/exe.au3`、`msi.au3`、`uv.au3` 或自定义模块。EXE 参数必须按该厂商核对。
5. 设置权限、架构、超时、验证路径和版本输出，加入目标方案。
6. 运行 `scripts/Check.ps1`、方案 `-Validate`。在测试机通过 `-Only <id> -Execute` 单项安装，确认日志及实际功能后再构建正式包。

## 配置字段

| 字段 | 约定 |
| --- | --- |
| `id` | 与文件名、清单中的 ID 完全一致 |
| `version` | 固定版本标签；空值或 TODO 阻止执行/构建 |
| `module` | 工作区相对 `.au3` 路径；模块及其依赖放在 `scripts/` 下 |
| `package` | 单个主安装包的工作区相对路径，禁止越过工作区 |
| `sha256` | 主安装包的完整 64 位 SHA256，不区分大小写 |
| `architecture` | `x64`、`x86`、`any`；x64 仅接受 AMD64 主机 |
| `requiresAdmin` | JSON 布尔值；执行器检查权限，不自动提权 |
| `timeoutSeconds` | 1..86400 整数；原生进程等待超时 |
| `arguments` | 原样作为厂商参数；支持 `%环境变量%` 与 `{logDir}` |
| `targetDir` | 可选目标位置，支持 `%环境变量%`；含义由模块决定 |
| `skipIfVerified` | 默认 false；true 时已通过验证的插件可跳过，需配置带版本的验证输出 |
| `verify.path` | 安装后的确切文件路径，支持 `%环境变量%`，不能留空 |
| `verify.arguments` | 非空时运行该文件验证，例如 `--version`；超时 30 秒 |
| `verify.contains` | 验证命令输出必须包含的字面字符串；建议带完整版本，例如 `uv 0.x.y ` |

若 `verify.arguments` 为空，只检查文件存在，适合初步接入 MSI；正式交付建议补充该软件支持的版本/功能检查。`contains` 是字面子串匹配，填写足够明确的版本字符串；不会从 `version` 自动推断或比较版本大小。安装器返回 0 后仍必须通过验证。

`verify.arguments` 支持 `%环境变量%` 与 `{root}`（当前工作区/交付包根目录）。例如 rustpm 插件调用包内 `scripts/Verify-Rustpm.ps1`，检查 MSI ProductCode、版本注册、已安装文件和两个服务的运行状态。验证脚本必须只读；无论是验证还是跳过判断，都不能重新安装或修改配置。

安装参数是给厂商的命令行，不经 `Invoke-Expression` 或 shell 二次执行。仍须正确加引号并避免把密码、令牌放入参数或日志。MSI 模块自动添加 `/i /qn /norestart REBOOT=ReallySuppress /L*v`，`arguments` 只填额外的厂商属性/参数，不能覆盖禁止自动重启的设置。

## 自定义 AutoIt 模块接口

自定义模块放到 `scripts/modules/<id>.au3`，用 `#include "..\lib\Common.au3"` 引入工具函数。入口通过当前进程环境接收：

| 环境变量 | 内容 |
| --- | --- |
| `DEPLOY_ROOT` | 工作区绝对路径 |
| `DEPLOY_PACKAGE` | 已校验主安装包的绝对路径 |
| `DEPLOY_ARGUMENTS` | 已展开占位符的参数 |
| `DEPLOY_TARGET` | 已展开环境变量的目标位置 |
| `DEPLOY_TIMEOUT` | 超时秒数 |
| `DEPLOY_LOG_DIR` | 当前插件本次日志目录 |

`_Exec(command)` 启动并有限等待进程；`_Start(command)` / `_Wait(handle, seconds)` 可用于需要中间操作窗口的流程。返回值：0 成功、3010 需要重启、1641 已启动重启、124 超时、其他非零失败。所有模块应原样返回安装器退出码，并将诊断写到 `ConsoleWrite`，由入口保存为 `module.log`。

复制 `templates/gui.au3` 到模块目录后，才开始修改其中的窗口选择器。模板默认拒绝运行，避免误点真实安装器。用 Au3Info 获取窗口/控件标识，为每一页设置有限等待和预期文本，逐步验证页面，优先 `ControlClick` / `ControlSetText`。不同语言、DPI、版本、权限与重启页面应在测试机验证。UAC 通过预先以管理员身份启动入口处理。

## 扩展边界

当前每插件管理一个主安装包。需要额外 MSI transform、离线依赖或多个文件时，可先封装为单个 ZIP，并编写独立模块解包执行；ZIP 的 SHA256 覆盖其内容。自定义辅助脚本放在 `scripts/`，构建时一起携带。不要依赖开发机绝对路径或未打包的文件。

无需把插件限制为某种最终产物：它可以安装软件、部署便携目录或执行环境配置，只需遵守有限超时、退出码与安装后验证约定。当前构建器输出可移植目录和 ZIP；若后续确定需要 EXE、MSI 或其他封装，可另增构建步骤，保留同一插件与方案接口。
