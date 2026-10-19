# 体验与性能校准

本轮在 13 套主题、117 个视觉实体与 182 段操作声音之上，对实际交互和资源生命周期做了复验。当前使用 Debug 开发版，没有生成安装包。

## 已修正的体验问题

- 当前装备按稳定任务 ID 记忆；移动、重排和换肤不会把任务与实体记混。
- 各主题分别记忆内置选择，修改一个主题不会改变其他主题的默认实体。自定义图片随任务跨主题保留。
- 空槽的细线加号可直接添加，移除控件保留点击范围；长枪与棍棒不会压住移除按钮。
- 从选择器收容窗口与拖拽收容使用同一套成功音效。
- 相同状态和相同内容的新时间戳不会把已读任务重新标为未读。
- 自定义声音先进入草稿；试听支持未保存文件。多个覆盖文件保存失败时回滚前面的写入，取消不会留下半套修改。
- 声音支持主题与实体两层覆盖；恢复实体默认时正确继承主题声音。
- 短屏总览的实体插画改为 Canvas 覆盖层，避免插画高度反向撑大父布局、无限重新排列。

## 已测量的资源变化

| 项目 | 调整前 | 调整后 |
| --- | ---: | ---: |
| 同一组九张永劫原图的运行时像素表面估算 | 54 MiB | 6 MiB |
| 轮盘绘制命令记录 P95，180 个暖帧 | 0.3031 ms | 0.1928 ms |
| 轮盘每帧托管分配均值 | 58,391 B | 14,643 B |
| 24 个真实状态事件批次的配置写入次数 | 每事件一次 | 整批一次 |

图片原文件没有被运行时缓存覆盖。显示副本最长边为 512 px，缓存按最近使用顺序淘汰，限制为 48 MiB 像素预算和 72 张图片；损坏或缺失文件使用短时负缓存，避免每帧重复读盘。导入流程与显示缓存分开，保留导入副本的高清细节。

音效在独立线程加载与混音，最多四个声音；连续切换不会排成长队。静音取消正在播放的声音，设备空闲后释放，工作线程随后等待事件。不同主题的同类操作做了响度校准，保留各自的材质和节奏。

设置中的静态圆盘、总览和状态预览不运行 Terminal GIF 定时器；只有可见的套装或 Terminal 动画预览才解码帧。隐藏或关闭预览会停止并释放相应资源。

这些绘制指标不包含系统合成、显示器刷新或原生窗口激活，不能当作端到端切窗延迟。像素表面是缓存尺寸估算；进程内存还包含 WPF、解码器与其他界面资源。

## 可重复检查

```powershell
dotnet run --project tools/suite-performance -c Debug -- artifacts/suite-performance/report.json
dotnet run --project tools/experience-audit -c Debug
dotnet run --project tools/game-audio-validation -c Debug -- artifacts/game-audio
dotnet run --project tools/settings-studio-validation -c Debug -- artifacts/settings-validation
```

程序还提供 `--self-test <report.json>`、`--loadout-test <report.json>` 和 `--wheel-benchmark <report.json>`。检查使用隔离样例，声音故障探针仅创建随机命名的临时实体目录，不操作真实 CLI 会话。

[整套原生实拍](../game-suite-refinement/index.html) · [音效试听](../game-audio/index.html) · [内容包规范](../../skins/loadouts/suites-v1/README.md)
