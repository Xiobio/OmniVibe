# 十套 Windows Terminal 配套皮肤

这十套外观与 OmniVibe 侧栏、任务总览共享 `skins/catalog.json` 色板和原创插画。Terminal 使用正常等宽字体显示代码；游戏风格出现在插画、外缘结构、颜色和光效中。

| 名称 | 命令中的标识 | 终端边饰与动效 |
| --- | --- | --- |
| 英雄联盟 · 海克斯枢纽 | `hextech` | 黄铜包边、棱晶嵌槽、齿环肩甲、青色导光 |
| 三角洲行动 · 战术终端 | `tactical` | 哑光合金、双层标尺、设备括角、局部扫描 |
| 无畏契约 · 行动协议 | `protocol` | 多面切角、珊瑚嵌板、分段指令轨道 |
| 地下城与勇士 · 冒险装备栏 | `adventure` | 锻钢包角、皮革缝线、铆钉与宝石嵌件 |
| 永劫无间 · 无间兵器匣 | `arsenal` | 成对长刃、玄铁铜轨、符印刻纹与余烬 |
| 黑神话：悟空 · 灵蕴法宝匣 | `relic` | 颗粒石材、台阶龛沿、回纹印记、旧金高光 |
| 王者荣耀 · 星曜指挥台 | `starlight` | 蓝色漆面、金色弧翼、切面玉石、星芒导光 |
| 金铲铲之战 · Agent 备战席 | `formation` | 珐琅槽位、圆润金框、备战格嵌件与分段光点 |
| 原神 · 星旅背包 | `astral` | 细金星盘、罗盘刻度、弧线星图与稀疏星点 |
| 梦幻西游 · 三界百宝袋 | `wonderland` | 青瓷釉边、暖金勾线、彩绘祥云、玉石点缀 |

2026-10-19 的细化版统一采用 **C：边框整体外移**，资源位于 `themes/windows-terminal/assets/refined-v1`。[修改前后图册](terminal-frame-refinement/index.html)包含十套逐项对比、窄窗口及 150% DPI 的离线预览，并可直接播放实际背景 GIF。

## 应用与切换

OmniVibe 设置 → 皮肤与侧栏可预览十套主题，保存应用原生界面；点击“应用配套 Terminal 外观”可单独切换终端，结果会显示备份路径。Terminal 默认使用同款静态插画与外框；背景动画需要单独勾选“Terminal 背景动画”，不随 OmniVibe 的界面动画自动启用。装饰选项独立控制插画，更新终端需再次点击应用按钮。

从项目根目录执行，必须明确指定一套皮肤。以下命令会修改本机 Windows Terminal 的外观配置，同时自动备份原配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin hextech
```

将 `hextech` 换成表中的其他标识即可切换。不需要结束终端中的任务。脚本不会创建新标签页或重启终端；如果已有标签页未刷新，可以自行新建一个标签页查看。

默认应用到 `profiles.defaults`；已有 profile 的单独外观可以继续覆盖默认外观。希望所有 profile 都统一使用这一套时，加上 `-AllProfiles`。它只调整外观，保留原有的命令、工作目录、GUID、环境变量、快捷键、默认 profile、字体和光标形状。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin wonderland -AllProfiles
```

默认保留插画与静态 C 边框，旧的 `-DisableEffects` 参数仍兼容：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin tactical -DisableEffects
```

需要背景动画时，显式启用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin tactical -EnableAnimation
```

动画版使用 Windows Terminal 的背景 Image 播放 GIF；默认静态版使用同款 PNG，不加载覆盖文字的 `experimental.pixelShaderPath`。边饰位于文字后面的背景层，不改变系统标题栏、窗口边框、拖动区域或关闭按钮。多窗口动画会增加持续解码和绘制开销，实测与修复见[终端性能记录](terminal-performance/README.md)。

`-DisableArtwork` 可独立关闭插画，保留静态边饰；同时加 `-EnableAnimation` 才会播放边饰动画。传入 `-DisableEffects -DisableArtwork` 只保留配色和阅读留白。`-EnableAnimation` 与 `-DisableEffects` 互斥。字体、字号和光标沿用原设置。

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

正文区域保留终端原始字形。结构边框及动态高光只绘制在 1280 × 754 参考背景最外侧 24 像素带，角部不超过 31 像素；动画不修改中央区域。GIF 每套 96 帧、100 ms / 帧、9.6 秒无限循环，不做全屏闪烁。

十套插画现已全部升级为完整环境画作：[实际效果总览](terminal-scene-gallery/index.html) · [源图与实际生成提示词清单](terminal-scene-gallery/README.md)。右侧主体保留，顶部建筑、左侧景物与底部地面连成同一场景。主画面不再叠加上一版的重复小纹样；关闭插画时，独立边框版本仍保留淡刻纹。场景细节烘焙进同一张 PNG / GIF，不加大 padding，不增加动画帧数或运行中的渲染层。

悟空主题进一步采用独立的 [完整洞窟插画](../skins/relic/terminal-scene-v2.png)：顶部石梁、左侧岩壁与石柱、底部石路连成完整场景，延续右侧石龛与玉璧。主画面不再叠加上一版重复的小回纹。目录中的 `terminalArtwork` 只指定 Terminal 源图，原 `artwork` 留给 OmniVibe 原生界面；原插画文件保留。构建时让边缘建筑更清晰，阅读区保留暗部空间，并继续校准全部 ANSI 对比度。关闭插画时仍使用独立边框资源。

永劫无间也采用独立的 [完整兵器阁插画](../skins/arsenal/terminal-scene-v2.png)：顶部木梁与梅枝、左侧雕花木柱与格栅、底部石台和反光地面与原右侧兵器架相连。同样通过 `terminalArtwork` 指定，不覆盖原生界面的插画，也不叠加重复的小纹样。

背景采用填充缩放。应用时根据当前所有显示器的逻辑尺寸计算保护留白，至少保留左右 36、上下 32 DIP，大屏可能增加留白；字号不变。该做法保证通常的单屏窗口缩放范围内边饰留在字形之外，代价是大屏配置下可用列数可能略减。改变显示器配置后需重新应用；跨多屏拉伸超过单屏尺寸时，仍应另行校准。读取尺寸只临时调整脚本线程的 DPI 上下文，并还原，不更改显示设置。依据：[显示器缩放](https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/nf-shellscalingapi-getscalefactorformonitor)、[线程 DPI 上下文](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setthreaddpiawarenesscontext)。

ANSI 16 色从共享色板派生。新版延续右侧原主体构图，左侧增加阅读遮光，顶部、左缘和底部保留更多环境细节，按实际插画像素做明度约束；解码后的 GIF 正文区域逐像素检验正文与全部 16 个 ANSI 色，对比度至少 4.5:1。亮色梦幻西游 · 三界百宝袋使用深色文字、深青/棕金/朱红状态色，不沿用深色主题的亮字。这里的语义色只是终端输出配色，不代表脚本能够自动识别终端中的任务状态。

细化版材质与矢量造型源为 `tools/terminal_frame_materials.py`，关闭插画时的静态刻纹源为 `tools/terminal_margin_details.py`，构建器为 `tools/build-refined-terminal-frames.py`。十套独立 Terminal 源图与实际提示词分别保存在 `skins/<标识>/terminal-scene-v2.png` 和同名 `.prompt.md` 中，通过目录的 `terminalArtwork` 引用；原 `illustration.png` 保留。构建器生成十套实际 GIF / PNG、关闭插画的独立资源及验证记录。旧 `shaders/designs/<标识>.hlsl` 保留为原设计参考；`Build-TerminalSkins.ps1` 继续生成色板与历史 HLSL，应用脚本不再加载这些后处理文件。

```powershell
python tools/build-refined-terminal-frames.py
python tools/build-terminal-scene-gallery.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Build-TerminalSkins.ps1 -Validate -RequireArtwork -ReportPath .\artifacts\terminal-skins-validation.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Test-TerminalSkins.ps1 -RequireArtwork
```

Python 构建验证实际 GIF 所有帧、中央区域静止、字形相交和实际对比度，输出 `assets/refined-v1/validation.json`。PowerShell 构建仍检查历史 HLSL 的真实编译与色板；应用测试只在隔离目录验证十套 C 资源、关闭动画、独立关闭插画、配置保留、JSONC、备份还原、BOM 和错误路径，不打开或操作真实终端。最终验收使用 `-RequireArtwork`。

原有墨玉及插画版仍保留，通过 [Apply-InkJade.ps1](../themes/windows-terminal/Apply-InkJade.ps1) 使用。

完整应用皮肤时也会统一原生顶部栏、标签页和系统细边框的配色，保留 Terminal 自带的按钮与操作。若只需让当前顶部栏与已有外框衔接，可在应用命令后加 `-ChromeOnly`，不会替换背景、字体或正文设置。细边框颜色需要终端版本与 Windows 支持；实现与验证见[原生顶部栏说明](../themes/windows-terminal/README.md#原生顶部栏与外框衔接)。

原生顶部配色已覆盖全部 13 套 UI 主题。三套经典主题通过 `-Skin ink-jade|midnight|cinnabar -ChromeOnly` 单独应用顶部配色，设置中也提供对应入口；不套用其他游戏的背景资源。`Apply-Skin.ps1 -RegisterAllChrome` 可一次更新全部 13 套原生定义，保留当前主题选择、背景和正文配置。十套游戏主题仍支持上面的完整插画与边饰应用流程。

依据：[Microsoft 外观配置](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance)、[Microsoft 窗口主题](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/themes)。
