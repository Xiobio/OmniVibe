# 窗口切换标志音修复

声音页选择的主题现在会保存，并传到实际窗口切换播放。默认「跟随界面主题」，也可以单独指定声音主题；隐藏设置页、切换预览主题和重新打开设置都不会丢掉显式选择。

旧版的问题有三处：声音页下拉框只用于试听，没有写入偏好；合成素材缺少游戏辨识度；轻声模式又把切换音截到约 140 毫秒。新版只在成功切换窗口时播放一个游戏标志音，完整保留其短音长度，其他操作保持安静。实际播放在独立线程解析声音主题和文件，不阻塞窗口切换，也不积压连续滚轮操作。

目前十套游戏声音均已安装：心之钢命中、无畏首杀、三角洲击杀、永劫官方手游振刀、原神传送、黑悟空菜单锣声前三秒、王者李白「神来之笔」、梦幻西游网页版战斗胜利提示，以及后续补齐的 DNF 鬼斩短语音与金铲铲官方活动点击音。具体来源与边界见[音源清单](../../skins/signature-audio/catalog.json)和[补齐验证](../signature-completion/README.md)。DNF 标为社区项目收录，金铲铲标为官方网页活动，不冒称已核对正式客户端音库；三个经典主题支持导入自定义声音。

自定义 WAV 仍采用草稿和原子事务：试听不落盘，取消不改变原文件，导入失败不半写声音或偏好。另修复了损坏 WAV 的 `InvalidDataException` 没有被保存流程捕获的问题。

[验证摘要](validation.json)保留首轮 39 组主回归、10 组声音设置检查、10 组音频引擎检查、10 组交互与事务检查记录。后续[十套完整播放验证](../signature-completion/validation.json)将每套保存为显式选择和跟随界面，送入真正的 `Manager.PlayCue`，检查二十次原生播放的实际路径、完整采样帧数、耗时与自然释放。声音探针使用 0.1% 音量，不操作真实 CLI。

十份音源通过 PCM 格式、时长、无削波、首尾与 SHA 校验，这些是技术检查，不代替听感判断。两个 Wiki CDN 的重新下载当前返回 403，已经下载并校验的本机缓存可正常使用；安装器保留已有缓存，逐项报告失败，不把部分重装称为全部成功。

[终端卡顿修复与同进程实测](../terminal-performance/README.md) · [安装和重新安装音源](../../tools/signature-audio/README.md)

```powershell
dotnet run --project tools/signature-settings-validation -c Debug -- --playback-all
dotnet run --project tools/game-audio-validation -c Debug -- artifacts/signature-refinement/audio-engine
dotnet run --project tools/experience-audit -c Debug
```

当前继续使用 Debug 开发版，未打包。
