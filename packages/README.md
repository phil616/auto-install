# 安装包目录

本目录只放经过来源核对的离线安装包，不提交版本控制。

首批预留位置：

| 插件 | 文件 |
| --- | --- |
| git | `git/Git-2.56.0.2-64-bit.exe`（官方 Git 2.56.0.windows.2） |
| uv | `uv/uv-x86_64-pc-windows-msvc.zip`（官方 uv 0.13.1 ZIP，含 uv.exe 与 uvx.exe） |
| vc-runtime-x64 | `vc-runtime-x64/VC_redist.x64.exe`（微软签名的 14.51.36247.0，MSI 前置依赖） |
| custom-msi | `custom-msi/rustpm-0.1.5-x64.msi`（从用户提供的根目录原件复制） |

记录原始来源、版本、架构和 SHA256。`Get-FileHash <文件> -Algorithm SHA256` 可计算摘要；摘要用于锁定文件，不能代替来源核对。

Git/uv 固定来源及官方摘要记录在 `tools/packages.lock.json`。运行 `scripts/Download-Packages.ps1` 可恢复相同版本；不会自动选择新版本或安装到本机。
