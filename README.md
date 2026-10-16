# OmniVibe

**The Open-Source Task Inventory for Vibe Coding**

让并行开发，像切换装备一样直觉。

OmniVibe 是面向多 AI Agent 并行开发的 Windows 桌面任务装备栏。将已有终端窗口收纳到 1–9 号槽位，通过快捷键快速切换，在任务总览中查看工作现场，并通过状态提示发现需要处理的任务。

项目以完全开源、可切换皮肤和社区自定义皮肤为目标。当前为本地开发版，源码及程序名称仍使用 `CodeManager`，技术栈为 C# / WPF / Win32。

## 当前能力

- 拖入或选择已有窗口，收纳、切换和排列任务。
- 使用 `Alt + 1–9`、`Alt + 滚轮` 快速进入任务。
- 使用 `Tab` 打开任务总览，查看窗口预览与任务状态。
- 接入 Claude Code / Codex hooks，显示运行、等待、本轮已回复等状态。
- 保存任务配置，重连窗口或恢复已配置的工作现场。
- 内置“水墨机关术”界面，提供墨玉、夜阑、朱砂配色及动画、声音设置。

社区皮肤包的导入、独立制作和分发属于后续建设目标，当前尚未提供完整开放皮肤机制。开源发布前还需确定并添加许可证。

## 快速启动

需要 Windows、.NET 10 SDK 和 Windows Desktop Runtime。在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

启动后，将终端窗口标题栏拖到侧栏空槽，或点击空槽选择窗口，再使用 `Alt + 编号` 唤出任务。右键任务可编辑信息和连接 CLI 状态。

当前按整个窗口绑定，不支持单独绑定 Windows Terminal 内部标签页或分屏。`Tab` 默认全局接管，会影响终端补全，可在设置中关闭或更改。

当前使用 Debug 开发版；`artifacts/CodeManager` 是不随源码更新的早期产物。退出工具会恢复其收起的窗口，CLI 继续运行。

## 文档

- [产品定义](docs/product-definition.md)：定位、核心交互、开放皮肤机制和首版范围。
- [使用与开发指南](docs/usage.md)：完整操作、快捷键、状态接入、数据恢复和开发检查。
