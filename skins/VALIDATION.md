# 十套皮肤检验与校准

校准日期：2026-10-16。原生应用以 Debug 开发构建验证，未生成安装包或发布压缩包。

## 实际界面图册

- [GitHub 可查看的图册](../docs/skin-gallery/README.md)
- [本地 HTML 图册](../docs/skin-gallery/index.html)
- 每套 `docs/skin-gallery/<slug>/preview.png` 包含真实 WPF 总览、侧栏、皮肤设置和右键菜单；由截图排版生成，不是概念效果图。
- `tools/build-skin-gallery.py` 使用 UTF-8 源码生成中英文标题、替代文本与图像说明，避免 Windows 管道默认编码将中文转换为问号。

每套原生界面渲染 13 种模式，共 130 张原始 QA 截图，保留在本地 `artifacts/skin-previews/<slug>/`：

| 范围 | 模式 |
| --- | --- |
| 总览及显示缩放 | `inventory`、`inventory-small`、`inventory-hidpi`、`inventory-short` |
| 常驻任务栏 | `compact`、`narrow`、`mini`、`expanded` |
| 菜单及设置 | `menu`、`settings-skin` |
| 任务和工作现场 | `task`、`integration`、`recovery` |

预览数据固定为六个已收纳任务与三个空槽：运行、等待处理、本轮已回复、错误、未知，以及独立的窗口断连；同时覆盖长中文/英文名称、未读、当前与选中。未接入真实 AI 会话，不包含用户任务文本。

## 自动检查

完整回归 27 组通过，其中新增皮肤相关检查 10 组。版本化结果见 [native-test-results.json](native-test-results.json)，最新构建与截图清单见 [native-validation-summary.json](native-validation-summary.json)。

皮肤检查涵盖：

1. 全部 13 套色板的正文、次级字、强调、五状态在主背景/面板/抬升面板上的对比，以及卡片正文和实际 80% 不透明度副文本对比均达到 `4.5:1`。
2. 十套新皮肤的 JSON 与原生枚举、全部色值、家族和插画路径一致；旧三套枚举 `0..2` 保持兼容。
3. 依次创建、更新全部皮肤的九张任务卡后，任务 ID、名称、会话、启动配置、窗口布局和唤出快照序列化结果保持一致。
4. 十套原创家族徽记像素结果均不同；关闭装饰后，徽记完全消失，背景保持精确纯色。
5. 窄侧栏保留专用 5 DIP 滚动条与正确模板，避免系统 Fluent 样式覆盖。
6. 设置中遍历 13 个选项验证稳定枚举标签；预览与取消不修改全局主题或传入偏好；真实保存提交正确皮肤与装饰开关，配置可序列化往返。
7. 在 780×650 与 200% 缩放总览中检查九张任务卡，预览区保留最小高度，可见状态文字边界处于预览范围内。
8. 全局主题滚动控件保留横纵 `PART`、命中范围与真实 `ScrollTo` / 行滚动操作。
9. 短工作区启用明确滚动回退；窗口保持在工作区内，真实自有窗口 DWM 预览可注册，裁切任务不绘制原生缩略图，末槽可选中、滚动并按 Enter 进入。
10. 在实际显示并加载完成的离屏窗口中，Slider 自动继承主题，保留原生 Track/Thumb、大步进命令和刻度吸附；现有菜单与下拉框 Popup 随动画设置动态切换 `None/Fade`，关闭动画后不再渐显。

测试创建和关闭自己的示例窗口，不启动用户 AI 会话，不修改真实 Terminal 配置。

## 发现并修正的问题

- 三界百宝袋初稿强调色在抬升面板对比不足，改为更深的 `#7C5918`。
- 星旅背包浅卡副文本原 72% 不透明度的复合对比不足，统一提高至 80%，并加入实际混色测试。
- 行动协议左编号轨、备战席底部信息条的重挂逻辑引发 WPF 重复父节点异常，跨皮肤任务卡测试发现后修复。
- 小屏下灵蕴与备战席装饰挤压预览：增加密度响应，减少边距与重复提示；高 DPI 保留编号、状态和任务名称。
- 工作区低于 420 DIP 时采用可滚动卡片，不继续压缩信息；滚动/动画时检查原生预览裁切边界。
- 系统默认粗灰滚动条与白色 Slider 不符合皮肤：统一使用主题模板，并验证真实滚动/步进能力。
- 亮色菜单、弹窗和设置使用独立深色正文，避免继承旧主题浅字/棕色面板。

对比与材质设计依据见 [DESIGN-CALIBRATION.md](DESIGN-CALIBRATION.md)。音效、动效绘图及生命周期检查见 [FEEDBACK-VALIDATION.md](FEEDBACK-VALIDATION.md)。配套 Windows Terminal 设置、插画、着色器与安全应用流程见 [Terminal 套装说明](../themes/windows-terminal/README.md)。

静态图册用于检查结构、状态区分、文字与皮肤差异；动画轨迹、音色和资源清理由独立验证工具检验。未将静态截图作为帧率或真实 GPU 流畅度的证明。

## 复现

```powershell
dotnet build src/CodeManager/CodeManager.csproj -c Debug -o artifacts/skin-dev
artifacts/skin-dev/CodeManager.exe --self-test artifacts/self-test.json
artifacts/skin-dev/CodeManager.exe --skin-test artifacts/skin-test.json
artifacts/skin-dev/CodeManager.exe --preview artifacts/example.png inventory-wonderland
```

预览模式均支持 `-<slug>` 后缀，并保持旧模式兼容。生成完整图册后运行 `python tools/build-skin-gallery.py`（需要 Pillow）。并行构建时为各任务指定独立 `IntermediateOutputPath`，避免 WPF 临时工程竞争。
