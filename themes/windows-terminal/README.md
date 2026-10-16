# Windows Terminal · 墨玉

新增十套完整游戏风格配套外观，见[十套皮肤说明](../../docs/terminal-skins.md)。通过 `Apply-Skin.ps1 -Skin <标识>` 明确选择；原有墨玉与插画版保持可用。

配套 OmniVibe 的终端外观：墨绿背景、暖白正文、青金红语义色、淡山水与八卦暗纹、Cascadia Mono 字体和轻微毛玻璃效果。

在项目根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1
```

脚本先备份现有 Windows Terminal 配置，再添加 `OmniVibe Ink Jade` 配色和窗口主题，并应用到默认外观。已有的终端配置、启动命令和快捷键保留。单独配置过外观的 profile 可能覆盖默认值。当前通过脚本单独应用，尚未与 OmniVibe 的皮肤选择自动联动。

## 插画与动态边饰版

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -Style Ornate
```

这一版包含云雷纹青铜边饰、玉石角饰、松鹤与山水楼阁插画，以及缓慢环绕的流光和边缘光点。正文周围增加留白，着色器保持中央文字原样，仅装饰内容区外缘。边饰属于终端内容画面，不改变系统标题栏按钮与窗口拖动区域。

动态效果使用 Windows Terminal 的实验性像素着色器接口，应用前通过本机 HLSL 编译检查。关闭动态效果并保留插画：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -Style Ornate -DisableEffects
```

省略 `-Style Ornate` 会切回简洁版并关闭该着色器。插画版使用独立的 `InkJadeOrnate` 资源目录，保留简洁版背景图。窗口宽高比例大幅改变时，插画会随背景填充缩放；着色器边框始终按当前内容区尺寸绘制。

插画由内置 image_gen 生成，正式资源为 [ink-jade-ornate-v2.png](assets/ink-jade-ornate-v2.png)，[完整生成提示词](assets/ink-jade-ornate-v2.prompt.md)随项目保存。

备份位于 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\Backups`，背景图位于 `%LOCALAPPDATA%\OmniVibe\TerminalTheme\InkJade`。脚本输出本次备份文件的完整路径，恢复方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\themes\windows-terminal\Apply-InkJade.ps1 -RestoreFrom '这里填入备份文件的完整路径'
```

恢复前也会备份当前配置。修改外观无需结束终端中的任务；如果现有标签页尚未刷新，可新开一个标签页查看。

参考：[外观配置](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance)、[窗口主题](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/themes)。
