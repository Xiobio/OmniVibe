# OmniVibe · 折光

新版品牌素材以紧凑的折面 V 为核心。墨黑、淡紫与暖白构成主色，图标和宣传图采用相同的平面图形与留白；折面动效保持轮廓稳定。

[打开预览](index.html) · [素材总览](brand-overview.png) · [下载整套素材](OmniVibe-brand-kit-v2.zip) · [小尺寸检查](icon-size-proof.png)

| 用途 | 文件 | 规格 |
| --- | --- | --- |
| Windows 桌面、EXE、托盘 | [ICO](icons/omnivibe.ico) | 16、20、24、32、40、48、64、128、256 px |
| 网页图标 | [favicon](icons/favicon.ico) | 16、32、48、64 px |
| 产品标记 | [透明 PNG](icons/omnivibe-product.png) / [SVG](logos/omnivibe-mark.svg) | PNG 1024 px；SVG 任意缩放 |
| 应用图标 | [PNG](icons/omnivibe-app-512.png) / [SVG](logos/omnivibe-app.svg) | PNG 另有 16–1024 px 导出 |
| 单色标记 | [白色](logos/omnivibe-white.svg) / [墨黑](logos/omnivibe-ink.svg) | SVG、1024 px PNG |
| 深浅底字标 | [深色底](logos/omnivibe-wordmark-dark.svg) / [浅色底](logos/omnivibe-wordmark-light.svg) | SVG、透明 PNG |
| 图标动效 | [SVG](motion/omnivibe-loop.svg) / [APNG](motion/omnivibe-loop.apng) / [GIF](motion/omnivibe-loop.gif) / [MP4](motion/omnivibe-loop-1024.mp4) | 4.8 秒循环；512 px；MP4 1024 px、30 fps |
| 发布封面 | [1920×1080](promo/launch-cover-1920x1080.png) | PNG |
| README 横幅 | [1600×600](promo/readme-banner-1600x600.png) | PNG |
| 社交分享 | [1280×640](promo/social-card-1280x640.png) / [1080×1080](promo/social-square-1080.png) | PNG |
| 功能介绍 | [1920×1080](promo/product-features-1920x1080.png) | 含原生任务轮盘的示例任务演示 |

透明动效使用 SVG 或 APNG；GIF、MP4 合成暖白底色。动效仅供品牌宣传使用，不代表任务状态，也不在程序内常驻播放。SVG 遵循系统的减少动态效果偏好。

## 使用与复现

保持图形比例和原有净空，小尺寸直接使用对应 PNG 或 ICO。深色背景使用白色版本。色值为墨黑 `#292831`、淡紫 `#CFC7E2`、折面紫 `#9280B4`、暖白 `#F7F6F2`。

SVG 是可编辑母版；字标文字使用 Segoe UI，可编辑字标跨平台展示时优先使用已导出的 PNG。没有捆绑字体文件。

在项目根目录运行：

```powershell
python tools/build-brand-v2.py
```

构建脚本：[build-brand-v2.py](../../../tools/build-brand-v2.py)。依赖 Pillow、imageio-ffmpeg；图形、尺寸、排版和动画均由本地几何源文件生成，不依赖旧版立体素材。功能图使用项目已有的 `docs/weapon-loadout/screens/radial.png` 组件演示，不作为真实任务状态证明。

EXE 和托盘图标引用这套 ICO，正常构建启动后生效。当前开发中的运行实例保留。发布图保留开发预览标识，产品能力及许可证状态以项目 README 为准。
