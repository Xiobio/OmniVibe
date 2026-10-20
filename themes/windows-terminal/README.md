# Windows Terminal · 墨玉

全部 13 套主题均提供完整 Terminal 套装，包括墨玉机关、玄夜青金、朱砂藏锋。设置中选择图片后点「保存并应用」，会同步 Terminal、圆环、槽位、总览与菜单；正在运行的 Terminal/CLI 会话继续保留。也可通过 `Apply-Skin.ps1 -Skin <标识> -AllProfiles` 单独调用应用器。

**默认使用精修静态 PNG，保留完整插画与外框。** 背景动画仅在显式传入 `-EnableAnimation` 时启用；设置界面也有独立且默认关闭的 Terminal 背景动画选项，不随 OmniVibe 的界面动画自动开启。多窗口 GIF 背景会持续解码与重绘，性能排查及实测见[终端性能修复记录](../../docs/terminal-performance/README.md)。

十套插画均已替换为完整环境画作，右侧主体与顶部、左侧和底部场景相连；[查看正式背景总览](../../docs/terminal-scene-gallery/index.html)及[独立源图与实际生成提示词](../../docs/terminal-scene-gallery/README.md)。插画关闭时仍使用独立边框，原生界面的原插画保留。

## 原生顶部栏与外框衔接

完整应用主题时会同时统一 Windows Terminal 的原生顶部配色：当前标签页与正文区同底色，其他标签融入顶部栏，窗口失焦时轻微压暗；系统细边框使用同套主题的低饱和强调色。标题栏、标签页、加号与窗口按钮仍由 Terminal 原生绘制和处理，不添加覆盖窗口、按钮替身或新的动画循环。

已有背景满意时，可以只更新顶部配色，例如永劫无间主题：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -Skin arsenal -ChromeOnly
```

顶部配色覆盖全部 **13 套主题**：十套游戏主题，以及 `ink-jade` 墨玉机关、`midnight` 玄夜青金、`cinnabar` 朱砂藏锋。三套经典主题现在也支持完整正文配色、独立插画、精修外框、静态 PNG 和可选动态 GIF。`-ChromeOnly` 仅作为手动只改顶部的兼容选项；设置保存始终应用整套。

一次注册或更新全部 13 套原生顶部配色，并保留当前选中的主题：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-Skin.ps1 -RegisterAllChrome
```

批量注册只更新主题定义，不切换当前主题、不修改 profiles，也不替换背景资源。已有主题的按钮显示方式、图标与 Mica 偏好保留；重复注册不产生重复项。游戏主题的生成清单也已包含新配色，重新生成或完整应用不会退回旧版。

墨玉插画版对应 `Apply-InkJade.ps1 -Style Ornate -ChromeOnly`。此模式只更新选中窗口主题，保留背景图片/GIF、字体、字号、padding、正文配色、命令、快捷键、标签布局与已有按钮行为；应用前会备份，可用原有 `-RestoreFrom` 恢复。已有 profile 的 `tabColor` 仍优先生效。

系统细边框受 Windows 与 Terminal 版本支持约束：已核对本机 Windows Terminal 1.24 的原生实现在 Windows 11 上应用边框色，在 Windows 10 上忽略这一项；顶部栏与标签配色可以独立生效。这里只改变原生颜色，不调整标题栏高度或系统按钮布局。

隔离验证：`Test-TerminalChrome.ps1` 检查 13 套主题及旧墨玉两种模式的配置保留、重复应用与备份恢复，并覆盖批量注册时的固定主题、随系统切换及未指定主题三种情况；同时核对所有配色与原生 UI 色板一致。原生行为依据 [Terminal 1.24 主题处理源码](https://github.com/microsoft/terminal/blob/v1.24.12741.0/src/cascadia/WindowsTerminal/AppHost.cpp#L902)及[原生主题配置](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/themes)。

配套 OmniVibe 的终端外观：墨绿背景、暖白正文、青金红语义色、淡山水与八卦暗纹、Cascadia Mono 字体和轻微毛玻璃效果。

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1
```

下方 `Apply-InkJade.ps1` 保留旧版墨玉背景的兼容入口。新的统一套装使用 `Apply-Skin.ps1 -Skin ink-jade -AllProfiles`。应用前自动备份，保留启动命令、工作目录、环境变量、字体与快捷键。设置保存会同步所有 profile 及其失焦外观，清除会压住所选配色的独立颜色覆盖；应用失败会在设置中显示错误并保留草稿。

## 插画与可选动态边饰版

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -Style Ornate
```

这一版包含云雷纹青铜外框、玉石角饰、松鹤与山水楼阁插画。默认显示静态插画与外框；需要沿外框移动的金色、玉青色流光时，在命令末尾追加 `-EnableAnimation`。终端文字层不再加载像素着色器，也不会在阅读区增加内框。

Windows Terminal 的 padding 位于文字渲染面板之外；旧着色器运行在文字面板之内，因此增大 padding 不能让细框自动避开文字。这次把装饰动画放回背景 Image 层，保留文字、光标、选区和鼠标交互的原始布局。边饰不改变系统标题栏按钮与窗口拖动区域。

如果已经在使用墨玉，只迁移背景和旧特效、保留现有字体、字号、padding、配色及其他偏好：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -Style Ornate -BackgroundOnly
```

脚本也迁移仍显式引用旧墨玉图片或旧着色器的 profile / `unfocusedAppearance`；其他 profile 的独立背景和自定义着色器保留。每次应用前备份原始配置字节，并通过临时文件原子替换；恢复会保留原始注释、换行和 UTF-8 BOM。

默认已使用原始 PNG 插画。以下旧命令仍兼容，可明确关闭动画：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -Style Ornate -DisableEffects
```

已有配置可在上述命令追加 `-BackgroundOnly`。省略 `-Style Ornate` 会切回简洁版。插画版使用独立的 `InkJadeOrnate` 资源目录，保留简洁版背景图。窗口宽高比例改变时，插画、外框及流光一起随背景填充缩放。背景装饰并不感知文字网格；保留 padding，不再往阅读区叠加一圈内框。

插画由内置 image_gen 生成，正式资源为 [ink-jade-ornate-v2.png](assets/ink-jade-ornate-v2.png)，[完整生成提示词](assets/ink-jade-ornate-v2.prompt.md)随项目保存。

动画为 [ink-jade-background-v5.gif](assets/ink-jade-background-v5.gif)：1586 × 992，200 帧、每帧 60 ms、12 秒无限循环。原插画不被覆盖；两束带尾迹的流光只沿现有外框移动，不再添加内框或内角花纹。中央插画在所有解码帧中保持静止。GIF 使用统一调色板，避免逐帧重新量化导致背景闪动。关闭动画时直接使用原 PNG。

显式启用动画的例子：`Apply-InkJade.ps1 -Style Ornate -BackgroundOnly -EnableAnimation`。`-EnableAnimation` 与 `-DisableEffects` 不能同时使用。

复现构建及隔离验证：

```powershell
# 需要 Python、Pillow 和 numpy；保留原插画，只渲染程序化边缘流光。
python tools/build-terminal-background.py
powershell -NoProfile -ExecutionPolicy Bypass -File themes/windows-terminal/Test-InkJadeBackground.ps1
```

验证覆盖全部 200 帧的中央区域不变、Windows 原生 GIF 解码、配置保留、失焦外观迁移、关闭动画、重复应用和逐字节备份恢复。记录见 [背景动画验收](ink-jade-background-validation.md)。旧 `ornate-frame-v2.hlsl` 保留用于历史参考，墨玉新应用流程不会再启用它；其他十套主题的独立实现见各自说明。

备份位于 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\Backups`；墨玉插画版资源位于 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\InkJadeOrnate`，简洁版位于 `InkJade`。脚本输出本次备份文件的完整路径，恢复方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -RestoreFrom '这里填入备份文件的完整路径'
```

恢复前也会备份当前配置。修改外观无需结束终端中的任务；如果现有标签页尚未刷新，可新开一个标签页查看。

参考：[外观配置](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance)、[窗口主题](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/themes)。
