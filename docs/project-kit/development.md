# 开发与维护

当前实现为 C# / WPF / Win32，目标框架 `net10.0-windows`，程序集名 `CodeManager`。先阅读 [贡献指南](../../CONTRIBUTING.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `src/CodeManager/` | 应用、窗口管理、交互、设置与测试入口 |
| `skins/` | 主题、配装、空槽代表物及来源 |
| `themes/windows-terminal/` | Terminal 外观、备份与验证 |
| `scripts/` | 验证与辅助流程 |
| `tools/` | 资源生成、清单和维护工具 |
| `assets/brand/v4/` | 当前仓鼠图标、尺寸导出与来源记录 |
| `docs/` | 指南、截图、设计与评测记录 |
| `artifacts/` | 本地产物与验证证据 |

文档入口见 [docs 导航](../README.md)。当前工作树仅保留正式展示与必要源素材；中间对比图和旧品牌可从固定的预览版标签回溯，见[整理记录](../project-footprint.md)。

## 源码入口

`App.xaml.cs` 负责启动和测试路由，`Manager.cs` 协调窗口；`Models.cs` 定义状态和偏好，`StateStore.cs` 处理持久化。`DockWeaponWheel.cs` 与相关 WPF 窗口负责交互，`EquipmentCatalog.cs` 管理配装，`StatusEventInbox.cs` 后台读取状态事件，`TerminalThemeService.cs` 连接主题设置与 Terminal 应用流程。

这些是源码导航，尚非稳定的插件 API。

## 构建与验证

在仓库根目录：

```powershell
dotnet build .\src\CodeManager\CodeManager.csproj -c Debug
powershell -ExecutionPolicy Bypass -File .\scripts\Validate.ps1
```

统一验证需要 Python，执行隔离 Release 构建、可靠性检查、英文适配检查、任务状态检查、监控脚本测试与资源清单生成。每组程序检查限制为 180 秒并保留单独 JSON。证据位于 `artifacts/validation/` 的独立目录。完整桌面检查额外运行皮肤与桌面自检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Validate.ps1 -FullDesktop
```

完整检查需要可交互 Windows 桌面；涉及焦点和输入，应在可控环境执行。数量与结论以本次 JSON 结果为准。文档修改只需检查内容、链接和展示，不必重启应用。

资源工具依赖见 [requirements-dev.txt](../../requirements-dev.txt)，编译主程序无需重新生成全部图片。

## 精简发布与清理

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\maintenance\Publish-Lean.ps1
powershell -ExecutionPolicy Bypass -File .\tools\maintenance\Clean-Generated.ps1
```

发布脚本默认输出 `win-x64` 框架依赖应用和资源清单，需要 .NET 10 Windows Desktop Runtime x64，不自动上传 Release。`-Runtime win-arm64` 可用于构建 ARM64 包，但须另行验证。清理默认仅预览，确认后按维护说明使用 `-Apply`。详见 [体积治理](../project-footprint.md)。

生成带安装说明、ZIP、SHA-256 和候选元数据的本地审查包：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\maintenance\Prepare-Preview.ps1
```

输出位于 `artifacts/release-candidates/`，命名为 `local-review`，不是已批准公开发行的版本。元数据记录基线提交和工作树是否有未提交改动；公开发行前应从确定提交重新生成、验收并核清素材范围。[安装、更新与回退说明](INSTALL.md)。

## 发布核对

- 从确定提交构建，保留本次测试结果与资源清单。
- 实测绑定、切换、拖动、右键关闭、主题应用和恢复。
- 验证输入冲突、多显示器、缩放与降低动效场景。
- 更新版本记录、截图说明与已知限制。
- 保留许可与来源说明，排除个人配置、日志和密钥。

历史报告：[代码评测](../reviews/2026-10-19-code-review.md)、[可靠性优化](../reviews/2026-10-20-reliability-optimization.md)。历史通过记录不替代当前提交验证。
