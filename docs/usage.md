# 目标电脑安装使用说明

本说明用于把已经构建、测试的交付包安装到其他 Windows x64 电脑。开发机上已有这些软件，不要用开发机重复安装代替测试。

## 整套安装

1. 将交付 ZIP 复制到目标电脑，完整解压至本地可写英文目录，例如 `C:\AutoDeploy`，不要直接在压缩包中运行。`Run.cmd` 应位于该目录根部；若解压工具多套了一层目录，进入实际包含此文件的目录。
2. 以目标使用者账户打开管理员 PowerShell，进入该目录。
3. 先预演、再预检，通过后才正式安装：

```powershell
cd C:\AutoDeploy

# 只看安装计划
.\Run.cmd

# 检查配置、安装包 SHA256、AutoIt 运行时与架构，不安装软件
.\Run.cmd -Validate
if ($LASTEXITCODE -ne 0) { throw '预检失败，请先检查错误输出' }

# 正式安装
.\Run.cmd -Execute
```

当前顺序：Git → uv → VC++ x64 运行库 → rustpm MSI。所有安装包与 AutoIt 运行时都在交付包中，无需事先安装 Git、uv 或 Python。测试曾开启网络以支持签名/证书检查，尚未完成完全断网验收。

`Run.cmd` 绑定的是构建时选择的方案，并显式调用系统 Windows PowerShell。不要把工作区根目录的 `Start.ps1` 命令与交付包根目录的 `Run.cmd` 混淆；工作区没有构建生成的 Run.cmd。

## 用户账户与 PATH

Git、VC++、rustpm 为当前配置下的机器级安装，需要管理员权限。uv 安装到**执行账户**的 `%USERPROFILE%\.local\bin` 并修改该账户用户 PATH。

如果用另一个管理员账号输入凭据启动整套安装，uv 会装到那个管理员账号下。要给普通用户安装 uv，可先由管理员逐项安装机器级插件，然后由实际使用者在普通 PowerShell 中安装 uv：

```powershell
# 在管理员 PowerShell 中执行
.\Run.cmd -Only git -Execute
.\Run.cmd -Only vc-runtime-x64 -Execute
.\Run.cmd -Only custom-msi -Execute
```

```powershell
# 切回实际使用者账户的普通 PowerShell，进入同一个可读写交付目录
.\Run.cmd -Only uv -Execute
```

安装目录的访问权限要让各执行账户能够写日志。`-Only` 不会自动安装依赖；单装 MSI 前必须准备 VC++ x64 运行库。通过 Run.cmd 调用时，以上示例一次传一个 ID，避免外部 `powershell.exe -File` 的数组参数传递差异。

## 安装后检查

全部完成后关闭旧终端，重新打开目标使用者的终端：

```powershell
git --version
uv --version
uvx --version
rustpmctl --help
Get-Service rustpm, rustpm-privd
```

版本应与交付方案一致；两个 rustpm 服务应处于 Running。uv 工具本身安装不代表已安装 Python、虚拟环境或 Python 项目依赖，这些需另行接入方案。

## 结果、失败和重启

安装入口打印本次 `logs/<时间>-<标识>/results.json` 路径。每插件有独立目录，Git 详细日志为 `git-setup.log`，uv 为 `uv-install.log`，VC++ 为 `vcredist.log`，MSI 为 `msi.log`，公共诊断为 `module.log` / `error.log`。

| 状态/退出码 | 含义与操作 |
| --- | --- |
| `installed-verified` | 安装器和安装后验证均成功 |
| `skipped-verified` | 验证已满足，插件允许跳过；当前 VC++ 插件启用此行为 |
| 1 或其他失败码 | 停止队列，先查看对应插件日志，不直接反复重跑 |
| 124 | 超时；实际安装器可能仍在运行，先检查 PID 与厂商日志 |
| 3010 / 1641 | 需要/已发起重启，后项未执行；处理重启后验证该项，再逐项继续 |
| `pending` | 尚未运行，不能视为安装成功 |

Git、uv、MSI 当前默认不因已安装就自动跳过。整套重复 Execute 可能重新运行这些安装器，不要用重复全量执行代替判断结果。

之前讨论的 `VerifiedAndReputablePolicyState=0` 与 `CiTool --refresh` 已封装为**沙盒测试兼容开关**，正式 Run.cmd 不自动执行。目标电脑若出现策略拒绝安装，应按该电脑实际策略和错误处理，不直接调用带 Sandbox 前缀的辅助脚本。

制作、测试或改变安装组合请阅读 [智能体操作手册](agent-playbook.md)，验收范围见 [测试方案](test-plan.md)。
