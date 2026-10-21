# 设置与主题中心

2026-10-19。[实际界面图册](index.html) · [自动验证](validation.json)

> 本文保留当时的设计与验证记录。当前设置导航见[设置与首次使用](../settings-and-onboarding/README.md)，主题保存与 Terminal 同步以[统一主题](../unified-themes/README.md)为准。

设置拆为主题套装、圆环与位置、窗口与排列、快捷键、常规与状态五区。导航、标题、内容分组与底部操作栏各自固定层级；正文区域可滚动，小窗口收紧侧栏宽度。

主题套装包含卡片浏览与五个预览页：整套效果、任务圆环、任务总览、Terminal、菜单与状态。可放大查看。选择主题保持为草稿，点击保存后由主程序应用；Terminal 有独立应用按钮和配置备份。浏览、取消或关闭设置不修改真实 Terminal 配置。

Terminal 预览逐帧解码实际 GIF，隐藏后停止更新，卸载后释放图像与流。每个预览只保留当前动画，不预解码全部帧。原生预览场景是组件布局示意，完整真实控件效果见[原生界面对比](../native-skin-refinement/index.html)。经典主题有明确的 Terminal 资源回退说明。

验证入口：[SettingsStudioValidation](../../tools/settings-studio-validation/README.md)。验证独立运行，读取实际 WPF 样式定义，不启动任务管理器或调用 Terminal 外观应用。
