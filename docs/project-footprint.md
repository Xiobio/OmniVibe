# 项目目录与体积维护

2026-10-21 再次整理。工作树以当前产品、必要的源素材、用户文档和可复现的验证工具为主。历史文件仍保留在 Git 和 [v0.1.1-preview](https://github.com/Xiobio/OmniVibe/tree/v0.1.1-preview) 中，没有重写历史，也没有改动已发布附件。

## 本轮删除

共移除 **456 个版本化文件，191,446,502 字节，约 182.6 MiB**：

- v1–v3 品牌图标、宣传导出、重复 ZIP 和对应的旧生成器；保留当前 v4 与探索来源。
- 已退役的 A/B/C 边框、早期原生组件、旧设置页的中间截图；保留评审文字、验证数值和历史入口。
- Terminal 图册的拼接图、紧凑与放大变体；保留全部 13 套常规预览。
- 未被当前清单引用、此前已排除出构建的 17 张旧空槽图片，以及关联的旧提示词。
- 被 v5 替代的墨玉 v3/v4 动画及旧验证文件。

全部在用的皮肤、配装、原创空槽伙伴、背景 PNG/GIF、音效、许可与生成提示词保持原样。早期截图链接指向固定预览版本；当前展示仍可从仓库本地打开。

## 目录约定

| 目录 | 保留内容 |
| --- | --- |
| `src/` | 应用源码与测试入口 |
| `skins/` | 当前界面素材、配装、音效、清单与来源 |
| `themes/windows-terminal/` | 当前 Terminal 背景、兼容入口、应用器和生成/验证工具 |
| `assets/brand/v4/` | 当前图标原图与尺寸导出 |
| `docs/` | 当前指南、精选预览和精简的历史记录；见[导航](README.md) |
| `scripts/`、`tools/` | 状态接入、构建、资源生成、验证与维护 |
| `artifacts/` | 忽略入库的本地产物、测试证据与发行包 |

`build-refined-terminal-frames.py` 默认只生成一张常规预览。需要额外尺寸时传 `--review-variants`，额外图写入 `artifacts/terminal-frame-refinement/`。历史 A/B/C 生成器输出到 `artifacts/terminal-frame-comparison/`。

## 本地构建缓存

```powershell
# 预览，随后执行同样的筛选
powershell -NoProfile -ExecutionPolicy Bypass -File tools/maintenance/Clean-Generated.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/maintenance/Clean-Generated.ps1 -Apply
```

清理只针对识别出的构建输出；报告、截图、状态、任务数据和源码快照不作为整体删除目标。保留运行中进程引用的目录、最近一小时写入的目录、正式发行证据、巡检、宣传视频和长期测试目录。路径及运行状态会在删除前复查，具体边界见[维护说明](../tools/maintenance/README.md)。

本轮清理 51 个本地构建目录，合计 **9,218,354,943 字节，约 8.6 GiB**。每个目录的处理结果与验证证据记录在 `artifacts/maintenance/`。这些是本机报告，不应作为其他机器的磁盘节省保证。清理完成后重新构建会产生新的缓存。

2026-10-20 的上一轮记录见 [历史文档](https://github.com/Xiobio/OmniVibe/blob/v0.1.1-preview/docs/project-footprint.md) 与[原始证据](reviews/2026-10-20-storage-evidence.json)。删除工作树文件不会同时缩小既有 Git 历史；本次不做历史清理。
