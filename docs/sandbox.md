# Windows Sandbox 安装验收

宿主机已安装 Git、uv、rustpm，不能通过在宿主机重跑安装来证明干净系统安装可用。使用 Windows Sandbox 完成安装测试。

逐步命令、8 项冒烟矩阵、报告断言及自定义方案适配见 [具体测试方案](test-plan.md)；测试通过后的同候选归档见 [构建与发布](build-release.md)。当前 Guest 固定 dev 四项，Host 入口没有 Profile 参数。

## 入口

1. 运行 `Start.ps1 -Profile dev -Validate`，随后 `scripts/Check.ps1` 与 `tests/Smoke.ps1`。
2. `scripts/Build.ps1 -Profile dev` 构建携带全部安装包的交付目录。
3. 执行 `scripts/Test-Sandbox.ps1 -BundlePath <上一步输出目录> -MsiCompatibilityWorkaround`；镜像不需要兼容设置时可省略该开关。
4. 查看打印出的 `logs/sandbox-<标识>/output/sandbox-report.json`，最终 `status` 应为 `passed`，四个步骤的退出码都应为 0。
5. 查看同目录的 `*-runner.log`、`*-check.log` 和 `deployment-logs/` 获取安装器与服务验证证据。

测试入口需要系统启用 Windows Sandbox，并提供 Windows 11 的 `wsb.exe` CLI。本机已确认 CLI 可用。系统仅允许一个活动沙盒；入口检测到已有会话会拒绝启动，不会自动关闭用户沙盒。关闭现有沙盒会丢失其中数据，必须先获得用户明确授权。

## 隔离方式

- 创建全新沙盒 ID，启动后首先检查 Git、uv 文件和 rustpm 服务都不存在；不满足时拒绝安装测试。
- 主机交付目录映射到沙盒 `C:\AutoDeployInput`，只读。
- 仅本次测试的输出目录可写，映射到 `C:\AutoDeployOutput`。
- 在沙盒内复制至 `C:\AutoDeployTest` 后，以 `WDAGUtilityAccount` 逐项执行 Git、uv、VC++ x64 运行库、MSI；各自的配置、版本、摘要及验证条件与正式交付相同。
- 关闭剪贴板、音视频输入、打印机映射与 vGPU。网络开启以允许 Windows 数字签名/证书链检查；本次安装包均已离线准备，不在沙盒中下载软件。该测试不能被描述为完全断网测试。
- `Sandbox-Guest.ps1` 检查沙盒账户及约定的映射源，拒绝在宿主机直接安装。

## 验证项目

Git：安装器退出成功、确切版本输出、新进程 PATH 下可执行。

uv：ZIP 解压部署、uv/uvx 文件、用户 PATH、确切 uv 版本，加载用户/机器 PATH 的新进程能够执行 uv 与 uvx。

VC++ x64 运行库：注册版本达到固定包版本或更新、x64 VCRUNTIME140.dll 存在，满足 rustpm 包的动态运行库依赖。

rustpm MSI：安装器退出成功、MSI 产品注册、注册版本 0.1.5、配置及 CLI 文件、`rustpm` 和 `rustpm-privd` 两个服务运行，以及 PATH 中 `rustpmctl --help` 成功。

四项均完成后脚本写入 `passed`，把日志复制回主机。任何错误记录为 `failed` 并停止后续步骤，不用主机已安装软件作为替代证据。

## 本机 Sandbox 的兼容条件

本次镜像的软件信誉策略初值为 2，MSI 的软件限制检查耗时约两分钟。微软 Sandbox 维护者在 [问题 #68](https://github.com/microsoft/Windows-Sandbox/issues/68) 中确认了这一现象及临时处理方法。

显式提供 `-MsiCompatibilityWorkaround` 时，`Sandbox-MsiCompatibility.ps1` 在检查 WDAGUtilityAccount 和沙盒映射后，将沙盒内 `HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState` 设为 0，执行 `CiTool.exe --refresh`，并在报告 `msiCompatibility` 中记录前后值。脚本默认不启用该开关，不将其加入正式安装方案；关闭测试沙盒即丢弃此修改。

策略调整解决检查延迟；rustpm 服务启动失败还需要独立的 VC++ 运行库前置插件。两者的验证证据分别保存在策略报告、MSI 日志和程序导入表中。

## 会话管理

启动脚本保存 `session.json` 和可复用的 `Test.wsb`。测试会话保留供检查；日志已导出后，可使用 `wsb.exe stop --id <session.json 中的 ID>` 关闭本次沙盒。只操作本次测试的 ID，不按进程名批量终止沙盒进程。

依据：[Microsoft Windows Sandbox CLI](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli)、[WSB 配置](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)。
