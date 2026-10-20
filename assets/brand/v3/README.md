# OmniVibe · Window Hub

两张薄荷绿窗口卡片收拢在深蓝终端之后，表达「多个窗口，一个入口」。中央命令提示符让图标与开发终端建立联系。使用简洁轮廓，减少小尺寸下的细碎装饰。

- [尺寸预览](index.html)：浅色与深色背景，16–256 px。
- [产品图标](icons/omnivibe-512.png)：透明 PNG。
- [Windows 图标](icons/omnivibe.ico)：16、20、24、32、40、48、64、128、256 px。
- [生成原图](source.png)：保留 imagegen 输出。
- [文件清单与哈希](manifest.json)。

## 来源

使用内置 imagegen 生成首稿，再以首稿为参考简化。没有引用游戏角色、厂商 Logo 或外部素材。提示词见 [prompts.md](prompts.md)。项目素材使用范围仍按根目录素材说明处理，不将生成记录当作独占商标或注册证明。

后处理仅进行 PNG / ICO 尺寸与格式导出，保留原始透明通道；没有描摹或声称 SVG 母版。复现导出：

```powershell
python tools/build-brand-v3.py
```

应用 EXE 与托盘均引用新 ICO，下次正常构建启动生效。本次不重启已有终端会话。v2 图标动画和宣传图属于旧版，不代表 v3。
