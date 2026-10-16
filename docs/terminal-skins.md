# 十套 Windows Terminal 配套皮肤

这十套外观与 OmniVibe 侧栏、任务总览共享 `skins/catalog.json` 色板和原创插画。Terminal 使用正常等宽字体显示代码；游戏风格出现在插画、外缘结构、颜色和光效中。

| 名称 | 命令中的标识 | 终端边饰与动效 |
| --- | --- | --- |
| 海克斯枢纽 | `hextech` | 黄铜齿环、青色棱晶、缓慢旋转的齿纹 |
| 战术终端 | `tactical` | 军绿标尺、琥珀括角、沿边慢速扫描 |
| 行动协议 | `protocol` | 珊瑚红切角、简洁指令短线 |
| 冒险装备栏 | `adventure` | 多层锻钢、铆钉、暖金锻造高光 |
| 无间兵器匣 | `arsenal` | 成对剑刃、赤铜交叉符印 |
| 灵蕴法宝匣 | `relic` | 台阶式石龛、旧金錾刻、低频灵蕴 |
| 星曜指挥台 | `starlight` | 技能徽记、玉色四芒星、同心光环 |
| Agent 备战席 | `formation` | 圆润备战格、棋盘刻度、环绕单位光点 |
| 星旅背包 | `astral` | 香槟星图细线、稀疏星点 |
| 三界百宝袋 | `wonderland` | 浅青瓷底、深色正文、彩绘祥云与玉带 |

## 应用与切换

OmniVibe 设置 → 皮肤与侧栏可预览十套主题，保存应用原生界面；点击“应用配套 Terminal 外观”可单独切换终端，结果会显示备份路径。设置中的动画与装饰开关也用于本次 Terminal 应用；随后更改开关时，需再次点击该按钮更新终端。

从项目根目录执行，必须明确指定一套皮肤。以下命令会修改本机 Windows Terminal 的外观配置，同时自动备份原配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin hextech
```

将 `hextech` 换成表中的其他标识即可切换。不需要结束终端中的任务。脚本不会创建新标签页或重启终端；如果已有标签页未刷新，可以自行新建一个标签页查看。

默认应用到 `profiles.defaults`；已有 profile 的单独外观可以继续覆盖默认外观。希望所有 profile 都统一使用这一套时，加上 `-AllProfiles`。它只调整外观，保留原有的命令、工作目录、GUID、环境变量、快捷键、默认 profile、字体和光标形状。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin wonderland -AllProfiles
```

只保留插画与配色、关闭像素着色器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin tactical -DisableEffects
```

动效通过 Windows Terminal 的实验性 `experimental.pixelShaderPath` 接口提供；某些版本或渲染配置可能不支持。`-DisableEffects` 无需这个接口。动态边饰属于终端内容区域，不改变系统标题栏、窗口边框、拖动区域或关闭按钮。

`-DisableArtwork` 可独立关闭插画；同时传入 `-DisableEffects -DisableArtwork`，只保留配色和阅读留白。字体、字号和光标沿用原设置。

## 备份和恢复

资源会复制到 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\<标识>\`，不依赖仓库位置或生成缓存。备份位于同目录下的 `Backups`，脚本输出本次完整路径。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -RestoreFrom '备份文件完整路径'
```

恢复前也会备份当前配置。还原保留原文件字节、注释、换行和 UTF-8 BOM。应用新皮肤时接受 JSONC 注释和尾逗号，输出格式化 JSON；原始排版可通过备份恢复。解析失败、插画缺失、着色器编译失败或发现配置在操作期间被其他程序修改时，会报错，避免覆盖配置。

`-SettingsPath` 可以指定 Preview 版本或便携版的配置文件；`-AssetRoot` 可以指定隔离资源目录。用它们测试副本不会影响实际终端：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin astral -SettingsPath .\artifacts\terminal-settings-copy.json -AssetRoot .\artifacts\terminal-assets
```

## 设计与校准

正文区域保留终端原始字形，着色器不扭曲、模糊或调色文字。装饰只作用于最外侧 24 DIP；配置预留左右 36、上下 32 DIP 留白，边饰与文字之间另有安全距离。流光低频运动，不做全屏闪烁。正文插画透明度固定 12%，窗口不透明，保证桌面背景不会影响阅读对比；外缘可以增强插画层次。

ANSI 16 色从共享色板派生，并逐色校准。在插画任何像素从纯黑到纯白的最坏混合条件下，正文和 ANSI 颜色与背景的对比度仍至少为 4.5:1。亮色三界百宝袋使用深色文字、深青/棕金/朱红状态色，不沿用深色主题的亮字。这里的语义色只是终端输出配色，不代表脚本能够自动识别终端中的任务状态。

每套边饰有独立形状源 `shaders/designs/<标识>.hlsl`；共享模板负责坐标、边界和采样。`Build-TerminalSkins.ps1` 从共享色板生成 `skins.json` 与十套独立可加载 HLSL，并可调用本机 Direct3D 编译器严格检查 `ps_4_0`，将警告视为错误：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Build-TerminalSkins.ps1 -Validate -RequireArtwork -ReportPath .\artifacts\terminal-skins-validation.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Test-TerminalSkins.ps1 -RequireArtwork
```

第一条检查十套 ANSI/正文最差对比、真实 HLSL 编译、插画存在与解码、最低清晰度。第二条只在隔离目录验证十套应用、关闭特效、配置保留、JSONC、重复应用不重复建色表、备份还原、BOM 和错误路径；不打开或操作真实终端。未加 `-RequireArtwork` 的开发测试可使用明确标记的图片夹具，最终验收必须加上它。

原有墨玉及插画版仍保留，通过 [Apply-InkJade.ps1](../themes/windows-terminal/Apply-InkJade.ps1) 使用。

依据：[Microsoft 外观配置](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance)、[Microsoft 窗口主题](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/themes)。
