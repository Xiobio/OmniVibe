# 发布前桌面冒烟与短时运行验证

在 Windows / .NET 10 的交互桌面运行。测试创建九个自有离屏窗口及独立配置，不连接个人 CLI，不读取个人会话正文；临时悬浮入口和托盘图标会出现。不要与其他桌面测试同时运行。

```powershell
dotnet build src/CodeManager/CodeManager.csproj -c Release -o artifacts/release-smoke/app
$assemblyPath = (Resolve-Path artifacts/release-smoke/app/CodeManager.dll).Path
dotnet build tools/release-smoke-validation/ReleaseSmokeValidation.csproj -c Release "-p:ProductAssembly=$assemblyPath" -o artifacts/release-smoke/app
artifacts/release-smoke/app/ReleaseSmokeValidation.exe artifacts/release-smoke/evidence 300
```

`ProductAssembly` 替换为本机绝对路径，工具输出目录与其一致，以使用实际素材。第二个参数为状态/展开/收起循环的秒数；加第三个参数 `--sample-only` 只采集未知、运行状态各 15 秒的 CPU 观察值，可用同一程序对比不同产品 DLL。

验证真实托盘消息、隐藏后心跳、双击防重复、状态切换与轮盘展开循环、预热后托管内存和句柄增长阈值、同配置重启重连、关闭窗口后清理槽位及保留历史。内存阈值是短时回归探针，不是长期稳定性的证明。CPU 按单个逻辑核心计算，结果受桌面活动和运行时版本影响；不能推广为所有机器的性能承诺。

证据写入指定目录：`cpu-samples.json`、`report.json` 或 `failure.txt`。没有打包、休眠、系统重启、多屏拔插、权限提升或真实 Agent 任务执行。

另可用 `ReleaseSmokeValidation.exe <证据目录> --observe-codex <已有记录路径> <会话 UUID>` 只读验证一个已完成的真实 Codex 回合。此模式调用产品本身的增量观察器，要求结果为 Ready；不会启动 CLI、修改记录或将聊天正文写入报告。仅使用自己有权访问的测试会话。

`ReleaseSmokeValidation.exe <证据目录> --monitor-smoke` 将一个自有测试窗口移到当前连接的每块物理屏幕，检查可见原点、显示器识别与最小化后恢复。使用产品同款 PerMonitorV2 清单；不改变系统分辨率、缩放比例或显示器连接状态，同缩放屏幕的通过结果不代表已验证混合 DPI。

`ReleaseSmokeValidation.exe <证据目录> --claude-chain` 用一个自有测试窗口和独立配置，经产品自带的 `scripts/Start-TrackedSession.ps1` 在最小化的 conhost 中启动一次真实交互式 Claude Code，提交一条无需工具的短提示，确认 hooks → 事件收件箱 → Running/Ready → 托盘提醒（系统回报气泡已显示）全链路，之后按任务 ID 结束该测试会话。会消耗一次真实请求；不修改全局 Claude 配置，不连接个人 CLI 窗口，不把回复正文写入报告。声音提醒在快捷键暂停时按设计不播放，此模式不验证音频输出。
