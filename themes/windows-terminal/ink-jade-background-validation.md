# 墨玉背景动画修正与验证

2026-10-19。本次仅修改墨玉插画版的 Terminal 背景与应用脚本，不改变 OmniVibe 原生界面或其他十套皮肤。

## 修正

旧 `ornate-frame-v2.hlsl` 在文字渲染面板内生成细框和角纹，可能与边缘字形重叠。新流程不加载 `experimental.pixelShaderPath`，同时关闭复古后处理；使用 Terminal 的背景 Image 播放 GIF，文字、光标与选区沿用 Terminal 原生渲染。

背景保留原山水、仙鹤与图片外框。根据阅读反馈，v5 取消 v4 额外绘制的内层双线框及四角机关花纹；两束金色、玉青色流光改为沿原插画外框行进。不把第二套角纹堆到外框上，也不往阅读区新增亮线。放在背景层只能保证字形的绘制顺序，不能消除装饰造成的视觉干扰。原 `ink-jade-ornate-v2.png` 文件保持原字节，关闭动画时仍可使用。

## 动画资源

- 1586 × 992、200 个不同帧、60 ms / 帧、12 秒无限循环；具体大小见动画数值记录。
- 全局统一 GIF 调色板，原插画只量化一次，没有新增静态内框；原 PNG 未修改。
- 对实际 GIF 逐帧完整解码：中央与所有非效果区的像素在全部 200 帧中保持一致。
- 效果带沿原插画外框，流光半宽 7 个资源像素。显式检查该效果带不进入原内框区域（归一化 x=0.025…0.960、y=0.040…0.940）。
- 按现有背景不透明度 0.5 检查，每帧至少 1,000 个像素的最大 RGB 通道变化大于 30/255，峰值至少 60/255，否则构建失败。此为资源可见性指标，不代替真实 Terminal 播放观察。
- 首尾跨越的变化量没有超过正常相邻帧的最大变化量。
- Windows 原生 GIF 解码器识别全部 200 帧；中心采样不变，边缘采样有动画变化。

生成器：[tools/build-terminal-background.py](../../tools/build-terminal-background.py)。原始生成检查输出到本地忽略目录 `artifacts/terminal-background/animation-validation.json`，版本化副本见 [动画数值记录](assets/ink-jade-background-v5.validation.json)。静态帧预览位于本地 `artifacts/terminal-background/outer-frame-000.png` 等文件。

## 配置与恢复

[Test-InkJadeBackground.ps1](Test-InkJadeBackground.ps1) 在隔离副本上验证：

- JSONC 注释、尾逗号和 UTF-8 BOM 输入。
- 默认 profile、显式旧墨玉背景、旧 shader 及失焦外观迁移。
- 背景迁移模式保留字号、字体、padding、配色、透明度和用户偏好。
- profile 命令、目录、GUID、环境变量、默认 profile、快捷键保持不变。
- 其他 profile 的独立图片和着色器保持不变。
- 重复应用、PNG 静态回退、完整 Ornate 应用均正常；新 Ornate 流程不再启用旧 shader。
- 备份与恢复逐字节一致，包括注释、BOM 和换行；非法模式拒绝且不覆盖配置。

隔离结果输出到 `artifacts/terminal-background/config-test/report.json`，版本化副本见 [配置验收记录](ink-jade-background-config-validation.json)。

本机实际迁移另验证：10 个 profile 数量不变，仅默认背景与后处理开关允许变更；字体、padding 和其他设置保持不变，安装资源哈希与仓库资源一致。没有重启终端或 CLI。实际配置备份和详细路径留在本机 `artifacts/terminal-background/live-migration.json`，不纳入仓库。

静态前景合成图仅用于层次与可读性检查，不作为真实 Terminal 截图或帧率证明。本次没有通过自动化操作 Terminal 界面，也没有生成安装包。
