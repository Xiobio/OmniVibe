# 配套终端与反馈验收

2026-10-16，Windows / .NET 10 开发环境。以下为真实资源最终验收；没有修改实际 Windows Terminal 配置，没有重启终端或 CLI，没有生成发布包。

## Terminal 十套

`Build-TerminalSkins.ps1 -Validate -RequireArtwork` 与 `Test-TerminalSkins.ps1 -RequireArtwork` 均通过。十张原创插画均可解码，尺寸均为 1586 × 992，最终行为测试的图片夹具数量为 **0**。

| 皮肤 | ANSI 16 色最小对比 | 正文最小对比 | HLSL 严格编译 |
| --- | ---: | ---: | --- |
| 海克斯枢纽 | 5.904 | 10.296 | 通过 |
| 战术终端 | 6.064 | 11.037 | 通过 |
| 行动协议 | 5.576 | 10.273 | 通过 |
| 冒险装备栏 | 5.643 | 9.226 | 通过 |
| 无间兵器匣 | 4.636 | 9.591 | 通过 |
| 灵蕴法宝匣 | 5.704 | 8.993 | 通过 |
| 星曜指挥台 | 5.197 | 9.008 | 通过 |
| Agent 备战席 | 5.531 | 9.706 | 通过 |
| 星旅背包 | 4.681 | 8.379 | 通过 |
| 三界百宝袋 | 4.560 | 8.298 | 通过 |

对比度包含正文区域 12% 插画与纯黑/纯白像素混合后的最坏情况。十个着色器均通过真实本机 Direct3D `ps_4_0` 编译，开启严格语法与警告视错误。字形中央采样直接返回原始颜色，装饰限制在 24 DIP 外缘，左右/上下分别预留 36/32 DIP。

十套均验证了：JSONC 注释/尾逗号、默认 profile/启动命令/工作目录/环境变量/快捷键/字体保留、重复应用无重复配色、独立 profile 选项、失焦外观同步、旧显式色值清理、关闭动画与插画、原配置备份还原。UTF-8 BOM 还原逐字节一致。8 个错误输入/缺少明确皮肤的情况均被拒绝且未覆盖配置。

复验方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File themes/windows-terminal/Build-TerminalSkins.ps1 -Validate -RequireArtwork -ReportPath artifacts/terminal-skins-validation.json
powershell -NoProfile -ExecutionPolicy Bypass -File themes/windows-terminal/Test-TerminalSkins.ps1 -RequireArtwork
```

## 原创反馈音

十套分别合成水晶齿环、设备卡扣、协议短音、锻钢锁扣、兵刃气流、石钵余音、技能清音、棋子落位、星旅玻璃与竹木轻音。每套有切换/收容两种变体，共 **20 个独立波形**，不使用外部音频或游戏声音素材。

格式为 22050 Hz / 单声道 / 16-bit PCM，切换约 105 ms，收容约 170 ms。20 个 WAV 均通过 `SoundPlayer.Load` 解码、SHA-256 唯一性、非静音、首尾平滑、无削波和 DC 偏移校验。

- 最大绝对峰值：0.0641 以下（满幅为 1）。
- 最小 RMS：0.00457 以上。
- 最大绝对 DC 偏移：0.000058 以下。
- 播放异步执行，130 ms 节流且最多一个播放任务；音频失败不会阻塞窗口操作。
- 验证不自动播放；可试听生成的 `*-switch.wav` 与 `*-capture.wav`。

## 视觉反馈与资源释放

Sweep/Ripple 使用当前色板和十种不同原生矢量徽记。窗口切换先立即执行，再出现短时反馈。全部覆盖窗为 `NOACTIVATE`、鼠标穿透；终止后解除计时器事件、清空内容并关闭窗口。

十套逐一验证覆盖窗不改变前台焦点，到期后活动租约为 0，WPF 窗口数量与实际可见原生 HWND 数量均回到基线。另验证：

- 60 次连续反馈始终最多保留 3 个覆盖窗。
- `CancelVisuals()` 立即释放所有覆盖窗。
- 关闭动画/装饰、不合法比例、已脱离界面的目标均不创建覆盖窗。
- 注入动画异常后窗口和计时器正常释放。
- 关闭声音的调用不进入播放流程。

托盘菜单的背景、文字、禁用文字、悬停、子菜单箭头、分隔线和勾选框均使用当前皮肤色板。十套离屏渲染成功，深色海克斯和浅色三界菜单已目检。十套真实 WPF 反馈徽记组成接触表，便于检查形状差异。

完整验证源保留在 [tools/feedback-validation](../tools/feedback-validation/README.md)。从仓库根目录运行：

```powershell
dotnet run --project tools/feedback-validation/FeedbackValidation.csproj -c Debug -- artifacts/skin-feedback-validation
```

引用的主程序构建输出位于隔离的 `artifacts/feedback-validation-app/`，不会覆盖正在运行的开发版。生成的 JSON 报告、20 个 WAV、10 张托盘菜单、10 张徽记与接触表位于参数指定目录；输出不纳入源码仓库。
