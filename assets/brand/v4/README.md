# OmniVibe · 窗口仓鼠

从 [动物方案板](../explorations/animal-concepts-01-12.png) 的 05 号方案精修：保留腮帮收纳两个窗口的特征，删除全身、脚掌与胡须，使用杏橙、奶油白与深棕，突出圆润的脸部轮廓和微笑。

此版本已由项目作者选定为当前项目图标，应用、托盘、README 和主题展示页统一使用。

[尺寸与深浅背景预览](index.html) · [512 px PNG](icons/omnivibe-512.png) · [ICO](icons/omnivibe.ico) · [原图](source.png) · [哈希清单](manifest.json)

原图通过内置 imagegen 编辑生成，参考为本项目动物方案板中的 05 号。后续通过 imagegen 移除外围发光。尺寸导出仅进行缩放与 PNG / ICO 格式转换，原图保留不动。提示词见 [prompts.md](prompts.md)。

PNG：16、20、24、32、40、48、64、128、256、512、1024 px。ICO 包含 16–256 px 的九个尺寸。

```powershell
python tools/build-brand-v4.py
```

README 与应用 EXE / 托盘资源引用此版本，应用端下次构建启动生效。生成图并非手工 SVG 母版；目前只更新静态图标，旧版宣传动画仍为历史版本。
