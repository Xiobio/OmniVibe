# 主题标志音

成功切换窗口时播放一个有辨识度的游戏音效。声音主题默认跟随界面，也可以在「设置 → 声音与反馈」单独选择，保存后生效。支持试听、音量、导入短 WAV 和恢复默认；其余操作保持安静。

十套游戏主题均已有对应声音：心之钢命中、无畏首杀、三角洲击杀、永劫手游振刀、原神传送、黑悟空菜单锣声、王者李白「神来之笔」、梦幻西游网页版战斗胜利提示、DNF 鬼斩短语音和金铲铲官方「小企鹅历险记」点击提示。三个经典主题可导入自定义声音。未安装的声音明确提示并保持静音。

DNF 鬼斩来自明确关联该技能的社区项目收录，尚未独立比对正式客户端音库；金铲铲使用官方活动网页的独立点击音，不冒称客户端升星音。该点击音做了恒定增益，避免原片过轻，未合成或改变音色。

[catalog.json](catalog.json) 记录具体音源、所属游戏、原始文件哈希和裁剪处理。仓库只保存清单与工具；音频安装到 `%LOCALAPPDATA%/CodeManager/SignatureAudio/<slug>/signature.wav`，游戏音频不混入旧的 CC0 合成素材库。

安装、来源边界与重装限制见[音源工具说明](../../tools/signature-audio/README.md)。

```powershell
python tools/signature-audio/install.py
python tools/signature-audio/validate.py
```
