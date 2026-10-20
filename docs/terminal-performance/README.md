# Terminal 背景性能修复与验证

2026-10-20：配套 Terminal 外观改为默认使用同款静态 PNG，保留插画、外框、配色和正文留白。背景动画改为单独选择；OmniVibe 的界面动画开关不会自动开启 Terminal GIF。

## 发现与实测

实际生效的 Windows Terminal 配置在 `profiles.defaults.backgroundImage` 使用「黑神话悟空 / relic」的 GIF：1280 × 754、96 帧、每帧 100 ms、无限循环。10 个 profile 均继承它，没有单独的非焦点静态背景。当前不启用 Acrylic、像素着色器或复古效果，透明度为 100；没有发现 TerminalChrome 覆盖层进程或相关运行任务。

旧 Terminal 进程 26972 在约 8 秒采样中占用单个逻辑核心的 95.15%，工作集约 1.27 GiB，OpenConsole 后端同期 CPU 很低。系统在北京时间 10:21:19–10:21:21 记录 WindowsTerminal 的 Application Hang / MoAppHang（事件 1002 / 1001）。旧进程随后已退出，环境更新后出现新进程 2900。调查和修复没有关闭 Terminal 或重启其中的 CLI；无法对旧进程补做同进程对照，也不能据此断言 GIF 是挂起的唯一原因。

下表是**新进程 2900 内**替换背景前后的三次独立约 8 秒采样：

| 背景 | CPU 时间增量 / 采样时长 | 单核占用 | 工作集 |
| --- | --- | --- | --- |
| 原 GIF | 2.8594 s / 8.0184 s | 35.66% | 182.10 MiB |
| 同款静态 PNG | 0.4063 s / 8.0036 s | 5.08% | 138.72 MiB |
| 静态 PNG 复测 | 0.4375 s / 8.0080 s | 5.46% | 138.71 MiB |

这里的百分比以一个逻辑核心为 100%，不是整机任务管理器百分比。这是短时现场 CPU / 工作集观察，没有控制终端输出负载，也没有测量输入延迟。结果支持取消持续背景动画能明显降低当前渲染负担；旧进程到新进程的内存变化不能归因于本次替换。

## 保留外观与配置

当前配置只将 `profiles.defaults.backgroundImage` 从 GIF 指向已有的同款 C 布局 PNG。原 PNG 为 1280 × 754，保留原插画及外层装饰；与 GIF 首帧中央 80% 区域的 RGB 平均绝对差为 0.9845 / 255，差异包含 GIF 调色板量化及边缘流光。

替换前完成逐字节备份，检查仅批准字段的语义变化，并保留 JSONC 注释、BOM 和其他文本。配色、字体、padding、窗口配置及会话相关字段保持原值。备份位于本机 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\Backups\settings-performance-20261020-025340-cda1fbc1.json`。这份含个人配置的备份不进入仓库。

后续使用方式：

```powershell
# 默认静态插画 + 外框
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin relic

# 单独选择背景动画；需要时才使用
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin relic -EnableAnimation

# 只保留静态外框
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin relic -DisableArtwork
```

`Apply-InkJade.ps1 -Style Ornate` 同样默认静态；`-EnableAnimation` 才选择动态版本。`-DisableEffects` 保留兼容，不能和 `-EnableAnimation` 同用。原生顶部配色模式与经典主题不启用背景动画。

设置页的「Terminal 背景动画」默认不勾选，与全局界面动画独立，经典主题下禁用。普通及放大预览跟随这一独立选择。关闭插画且关闭动画时，静态外框仍会显示。动画预览在隐藏及卸载后停止播放。

## 验证

所有脚本测试使用隔离配置，没有在用户终端运行测试命令。WPF 验证只构造设置窗口和预览，不启动外观应用器；测试前后实际 Terminal 配置哈希保持一致。

| 检查 | 结果 | 本地证据 |
| --- | --- | --- |
| 10 套游戏静态默认、显式 96 帧动画、无插画组合、配置保留与恢复 | 10/10；无占位插画 | `artifacts/terminal-lag-audit/script-tests/report.json` |
| 非法 / 冲突参数拒绝且配置不变 | 10/10 | 同上 |
| 墨玉静态默认、显式 200 帧动画、Windows 原生解码及恢复 | 通过 | `artifacts/terminal-lag-audit/ink-jade-tests/report.json` |
| 13 套原生顶部配色 + 2 个旧接口，3 种批量注册状态 | 15 + 3 通过 | `artifacts/terminal-lag-audit/chrome-tests/report.json` |
| 独立动画勾选框、实际脚本参数、经典主题禁用、配置只读 | 4/4 | `artifacts/terminal-lag-audit/ui-validation/report.json` |
| 13 套设置预览、静态外框可见、动画生命周期、短屏及保存语义 | 6/6 | `artifacts/terminal-lag-audit/settings-validation/report.json` |

更多采样与脱敏现场证据：`appearance.json`、`background-media.json`、`process-sample-1.json`、`hang-events-sanitized.json`、`new-process-before-static.json`、`new-process-after-static.json`、`new-process-after-static-repeat.json`、`static-background-change.json`、`static-artwork-check.json`，均位于 `artifacts/terminal-lag-audit/`。这些本机调查产物由 Git 忽略；仓库保留本页和 [验证摘要](validation.json)，不上传个人 Terminal 配置。

复现 UI 参数检查：

```powershell
dotnet run --project tools/terminal-performance-validation/TerminalPerformanceValidation.csproj -c Debug -- artifacts/terminal-lag-audit/ui-validation
dotnet run --project tools/settings-studio-validation/SettingsStudioValidation.csproj -c Debug -- artifacts/terminal-lag-audit/settings-validation
```

本轮没有打包，也没有重启任何用户 CLI。
