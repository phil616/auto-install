# 环境说明

## 开发机与目标机

- 本工作区初始按 Windows 10/11 x64 设计；目标系统具体版本尚待确认。
- PowerShell：Windows 内置 5.1 即可。执行链测试明确使用 5.1；开发机当前为 PowerShell 7.6.7。
- 交付包 `Run.cmd` 明确调用系统 Windows PowerShell，并在子进程范围内重置内置模块搜索路径，避免从 PowerShell 7 启动时继承不兼容的模块路径。
- AutoIt：3.3.18.0，使用官方完整便携 ZIP，无需全局安装或修改 PATH。
- 目标机运行交付包不需要预先安装 AutoIt、Python、Git 或 uv。
- 图形界面安装插件需要保持桌面登录、解锁；不要在非交互服务会话中运行。
- 工作区与交付包建议放到英文目录，如 `D:\AutoDeploy`，允许空格。本次验收发现官方 Au3Check 在中文工作区路径下不能可靠解析 include，`Check.ps1` 会给出明确提示；安装器/验证文件的中文路径已单独通过执行链测试。
- 当前三个插件配置均为 x64 包；ARM64 或 x86 需要选择匹配安装包并单独验证，当前 x64 声明会拒绝 ARM64。

## 工具位置

| 文件 | 用途 |
| --- | --- |
| `tools/autoit/install/AutoIt3.exe` | AutoIt 解释器，当前执行入口使用此版本 |
| `tools/autoit/install/AutoIt3_x64.exe` | 64 位解释器，暂未作为默认入口 |
| `tools/autoit/install/Au3Info_x64.exe` | 采集窗口标题、类名、Control ID、ClassNN |
| `tools/autoit/install/Au3Check.exe` | AutoIt 语法检查 |
| `tools/autoit/install/Aut2Exe/Aut2exe.exe` | 可选编译工具，当前交付使用便携脚本包 |
| `tools/autoit/install/SciTE/SciTE.exe` | 随包提供的基础编辑器 |
| `tools/autoit/install/AutoIt.chm` | 离线帮助 |

运行 `scripts/Bootstrap.ps1` 可恢复工具。ZIP 的 SHA256 锁在 `tools/autoit.lock.json`，这是本次从官方 HTTPS 下载后记录的摘要，并非官方独立公布的摘要。另验证解释器版本及 AutoIt Consulting 数字签名。

官方下载链接随未来发布可能变化。若摘要失败，核对官方版本、签名和来源后再显式更新锁文件，不要自动接受新摘要。不要删除下载包原有许可证；构建会保留完整 `install` 目录。

## 安装范围

Git 插件目前声明需要管理员，采用厂商默认安装位置并验证 `%ProgramW6432%\Git\cmd\git.exe`；若目标已有非标准路径或需用户安装，修改参数、权限声明和验证路径。

uv 插件安装到当前运行账户的 `%USERPROFILE%\.local\bin`，复制 `uv.exe`、`uvx.exe`，补充该账户的用户 PATH。只改用户 PATH；需要打开新终端加载。若通过另一管理员账户执行，安装对象会变成那个账户，因此用户级安装应在预期使用者账户下执行。

uv 工具本身不需要 Python。Python 版本、虚拟环境、Python 包依赖和离线缓存尚未纳入首批方案，应按需要分别新增插件。

uv 解压使用 .NET `System.IO.Compression.ZipFile`，避免部分中文 Sandbox 镜像缺失 PowerShell Archive 模块语言资源时安装失败。AutoIt 启动系统工具使用原生位数的目录，32 位解释器在 x64 Windows 通过 Sysnative 启动 PowerShell/msiexec。

首批安装包已固定为 Git 2.56.0.windows.2、uv 0.13.1。`tools/packages.lock.json` 记录固定下载地址和 GitHub 官方发布摘要；`scripts/Download-Packages.ps1` 可复现下载并校验文件。Git 安装器还通过了数字签名校验，签名人为 Johannes Schindelin。

根目录 `rustpm-0.1.5-x64.msi` 已只读解析 MSI 数据库，并复制到 `packages/custom-msi/`。安装包声明机器范围，安装 `rustpm` 和 `rustpm-privd` 两个自动启动服务，CLI 入口位于 `Program Files\rustpm\cli`；没有在宿主机执行该 MSI。

干净沙盒中，包内程序依赖 `VCRUNTIME140.dll`，缺失时程序退出 `0xC0000135`，导致服务启动超时、MSI 返回 1603。`vc-runtime-x64` 插件安装微软签名的 VC++ 运行库 14.51.36247.0，并验证 x64 运行库注册及 DLL，位于 `custom-msi` 之前。已有相同或更新运行库时通过验证后跳过安装。

## 官方资料

- [AutoIt 下载与版本](https://www.autoitscript.com/site/autoit/downloads/)
- [AutoIt 文档](https://www.autoitscript.com/autoit3/docs/)
- [控件定位与 Au3Info](https://www.autoitscript.com/autoit3/docs/intro/controls.htm)
- [Git for Windows 静默安装参数](https://github.com/git-for-windows/git-for-windows.github.io/blob/main/content/silent-or-unattended-installation.md)
- [uv 安装](https://docs.astral.sh/uv/getting-started/installation/)
- [uv 存储位置](https://docs.astral.sh/uv/reference/storage/)
- [Microsoft MSI 命令行选项](https://learn.microsoft.com/en-us/windows/win32/msi/standard-installer-command-line-options)
