# 任务完成提示音

十三套主题各有一段 0.32–0.55 秒的短音，来自 Versilian Studios / Sam Gossner 的 VCSL 真实乐器录音；根据主题选择铃树、钟琴、管钟、拇指琴、木质轻击。它们是主题意象的原创适配，不冒称游戏原声。

仅截取、恒定增益和平滑收尾，无合成音、变调、循环或叠加。播放使用共享音量的一半，与窗口切换音区分。所有主题离线可用，无额外播放器、下载或运行时 FFmpeg。

素材以 [CC0 1.0](../signature-audio/bundled/VCSL-CC0.txt) 提供。来源固定为 VCSL 提交 `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e`，每条源文件的 Git blob、SHA-256、处理参数和产物校验见 [catalog.json](catalog.json)。

重建：`python tools/signature-audio/build-completions.py`。维护脚本需要 Python、网络与 FFmpeg；使用工具不需要。
