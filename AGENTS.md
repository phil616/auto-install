# 工作区约定

接手先读 [智能体操作手册](docs/agent-playbook.md)，按 [具体测试方案](docs/test-plan.md) 验收，再按 [构建与发布](docs/build-release.md) 归档。目标电脑使用方式见 [安装使用说明](docs/usage.md)。

- 用户目标：AutoIt v3 驱动其他 Windows 电脑的软件安装；插件与交付方案可独立组合。
- 使用中文维护文档。PowerShell 兼容 Windows PowerShell 5.1；AutoIt 固定 3.3.18.0。
- `config/plugins/*.json` 定义插件，`config/profiles/*.json` 定义顺序，`scripts/modules/*.au3` 实现安装。
- 默认运行必须是预演。只有显式 `-Execute` 才能安装；环境检查、构建、测试不得安装真实软件。
- 接入插件必须提供固定版本、安装包 SHA256、权限/架构声明、有限超时及安装后验证。
- 优先使用厂商静默参数；窗口自动化优先控件定位，禁止无条件连续点击“下一步”。
- 安装包、日志、工具二进制和交付压缩包不提交。不要存储密码、令牌、许可证密钥。
- 超时停止队列，安装进程可能仍在运行，不能自动重试或按名称批量杀进程。
- 修改执行链后运行 `scripts/Check.ps1` 与 `tests/Smoke.ps1`；真实安装验证在测试机逐项进行。
- 本机已安装 Git、uv、rustpm，禁止在宿主机上执行真实软件安装测试。使用 `scripts/Test-Sandbox.ps1` 创建干净 Windows Sandbox；原有沙盒会话只能在用户明确允许关闭后结束。
- 当前 Sandbox Guest 固定 `dev`、四个插件及对应初始/CLI 检查；新增方案必须同步适配测试，不能假定 Host 入口可自动测试任意方案。
- 最终交付必须对应实际验收的候选目录。Build 不自动附验收报告；添加 validation/ 后重建文件清单、压缩并核对 ZIP 摘要。旧包和旧报告不会随源文件自动更新。
