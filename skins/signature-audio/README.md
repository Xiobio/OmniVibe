# 主题标志音

成功切换窗口时播放一个有辨识度的游戏音效。声音主题默认跟随界面，也可以在「设置 → 声音与反馈」单独选择，保存后生效。支持试听、音量、导入短 WAV 和恢复默认；其余操作保持安静。

本机已安装心之钢命中、无畏首杀、三角洲击杀、永劫手游振刀、原神传送、黑悟空菜单锣声、王者李白「神来之笔」和梦幻西游网页版战斗胜利提示。DNF 与金铲铲的原声仍待确认；三个经典主题可导入自定义声音。未安装的声音明确提示并保持静音。

[catalog.json](catalog.json) 记录具体音源、所属游戏、原始文件哈希和裁剪处理。仓库只保存清单与工具；音频安装到 `%LOCALAPPDATA%/CodeManager/SignatureAudio/<slug>/signature.wav`，游戏音频不混入旧的 CC0 合成素材库。

安装、来源边界与重装限制见[音源工具说明](../../tools/signature-audio/README.md)。

```powershell
python tools/signature-audio/install.py
python tools/signature-audio/validate.py
```
