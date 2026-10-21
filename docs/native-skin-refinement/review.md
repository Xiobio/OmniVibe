# 原生组件细化

2026-10-19。[十三套实际界面对比](index.html) · [收起圆环细节](https://raw.githubusercontent.com/Xiobio/OmniVibe/v0.1.1-preview/docs/native-skin-refinement/core-before-after.png) · [新版设置](../settings-studio/index.html)

> 历史设计记录。中间截图和旧图册生成器已转由固定预览版档案保留；当前完整组件展示见[13 套图册](../game-suite-refinement/index.html)。

这一轮覆盖十套游戏风格与墨玉机关、玄夜青金、朱砂藏锋三套经典主题。

- 核心采用分层材质、刻槽、嵌件与独立轮廓：齿轮、八角设备、六边协议、锻装铆钉、兵刃、石刻、星翼、珐琅、星盘、云纹等；中心透明区域保留任务身份徽记。
- 槽位与任务徽记使用同套材质底座。外饰按九切片拉伸，保留角部比例；细节资源与 Terminal 共用可编辑的材质源。
- 任务总览的外框与卡片增加分层边饰、编号铭牌和轻量插画底层。动态窗口缩略图继续位于预览区；占位状态文字缩小并统一字重。
- 小窗口收紧装饰宽度；空槽降低边饰强度。正文不参与后处理着色器。
- 图像与分片绘图使用冻结缓存，尺寸缓存最多 256 项；任务徽记缓存包含主题及装饰开关，切换主题与关闭装饰时不会沿用旧素材。

## 验证

真实 WPF 离线渲染：每套保留修改前三种视图，以及修改后的圆环与槽位、任务总览、收起圆环、小窗口、200% 缩放布局，共 104 张截图。图中使用固定示例任务，未读取真实会话内容。

- 原生皮肤检查 21 组通过，涵盖固定槽位、透明范围、任务数据、枚举兼容、设置提交、短窗口、高 DPI、缩略图裁切与反馈生命周期。
- 设置中心 6 组验证通过，覆盖十三套主题与五种预览、保存边界、真实 GIF 帧变化、隐藏及卸载后的动效停止、小窗口操作栏与滚动、真实 Terminal 配置未改动。
- 所有核心资源的内圈半径 62 像素内、外圈半径 125 像素外保持透明；原始插画未修改。

证据：[材质资源验证](../../skins/native-v2/validation.json)、[设置验证](../settings-studio/validation.json)。完整原生检查记录与源截图保留于本地 `artifacts/native-polish/`；静态截图不证明实际 GPU 帧率。

构建入口：[build-native-skin-art.py](../../tools/build-native-skin-art.py)、[build-native-refinement-gallery.py](https://github.com/Xiobio/OmniVibe/blob/v0.1.1-preview/tools/build-native-refinement-gallery.py)。本轮使用 Debug 开发构建，没有打包。
