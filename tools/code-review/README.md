# 本地代码评测工具

这些工具读取仓库源文件，并把证据写入 `artifacts/code-review/`。不要把个人任务配置、终端设置或本地凭据复制到报告目录。

## 仓库快照

```powershell
python tools/code-review/review-snapshot.py --decode-raster
```

记录源文件哈希、物理行数、文件体积、Python / XML / SVG 语法、图片首帧解码和本地文档链接。强格式令牌扫描只输出文件、行号与类型，不输出匹配值；它不能替代完整安全审计。GIF 全帧另用项目原生验证脚本检查。

## 隔离构建与诊断探针

确认开发任务结束后，在项目根目录执行：

```powershell
dotnet build src/CodeManager/CodeManager.csproj -c Release -o artifacts/code-review/app
dotnet run --project tools/code-review/ReviewProbe.csproj -c Release -- artifacts/code-review/probes .
```

探针仅引用隔离构建中的程序集，不启动任务管理器，不注册全局输入钩子，不读取个人任务，也不应用终端外观。它测试损坏 JSON 的恢复路径、嵌套空字段的容错，并在单独进程中批量解码最多 90 张实际配装图。

`probes/report.json` 包含发现项，进程退出码 0 仅表示诊断成功完成。图片压力测试的内存和耗时包含 WPF / 原生解码器初始化，不等于主程序日常常驻内存。不能将这些数据解释为跨机器性能保证。

## 产品现有验证入口

在隔离构建中运行 `CodeManager.exe --self-test <结果.json>`、`--loadout-test <结果.json>` 和 `--wheel-benchmark <结果.json>`。完整自检已包含皮肤检查，统计报告应按测试组计数，不应重复相加后宣称是独立测试数量。轮盘基准只测界面线程的绘图记录时间，不包含系统合成、窗口激活和真实输入延迟。

Terminal 验证脚本位于 `themes/windows-terminal/Test-TerminalSkins.ps1`、`Test-TerminalChrome.ps1` 和 `Test-RefinedFrames.ps1`。前两者在临时配置副本中验证写入与恢复；运行前应检查参数，避免误用真实用户配置。
