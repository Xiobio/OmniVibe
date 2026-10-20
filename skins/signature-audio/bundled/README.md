# 经典主题的默认标志音

| 主题 | 声音 | 实录素材 | 时长 |
| --- | --- | --- | --- |
| 墨玉机关 | 玉铃清鸣 | Bell Tree / E5 | 1.05 秒 |
| 玄夜青金 | 星钟微光 | Glockenspiel / C6 | 1.45 秒 |
| 朱砂藏锋 | 铜钟落印 | Tubular Bells / C3 | 1.25 秒 |

三段均来自 Versilian Studios / Sam Gossner 的 [VCSL](https://github.com/sgossner/VCSL) 真实乐器录音，按各主题选材、截取、调整恒定增益并平滑收尾。没有合成波形、变调、压缩、叠加或循环。名称为主题意象，不声称录制了玉石或中国编钟。

上游提交固定为 `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e`。素材以 [CC0 1.0](VCSL-CC0.txt) 发布，可以随工具提供，完整来源、处理参数和 SHA-256 见上级 `catalog.json`。

运行 `python tools/signature-audio/build-classics.py` 可从固定校验的源文件重建；只用于维护，不是用户首次启动的必要步骤。运行时离线可用，无需下载、FFmpeg 或额外安装。手动导入和已有本地声音仍然优先。
