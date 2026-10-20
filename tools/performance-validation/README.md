# 性能回归基准

在 Windows / .NET 10 下对**同一测试程序**分别引用优化前后的 `CodeManager.dll`。覆盖窗口身份、重复快捷键配置、普通鼠标移动、24 个未变化会话的发现、4 个已连接会话的轮询，以及轮盘展开过程和稳定展开后的绘制。

```powershell
dotnet build src/CodeManager/CodeManager.csproj -c Debug -o artifacts/performance/baseline-bin
dotnet build tools/performance-validation/PerformanceValidation.csproj -c Debug -p:ProductAssembly=D:\tools\OmniVibe\artifacts\performance\baseline-bin\CodeManager.dll -o artifacts/performance/baseline-bin
artifacts/performance/baseline-bin/PerformanceValidation.exe artifacts/performance/before
```

修改代码后换用 `after-bin` 和 `after` 重复。`ProductAssembly` 要用本机实际绝对路径，输出目录与它一致，确保测试使用同一套实际素材。程序只使用自行创建的会话和后台示例窗口，不读取聊天正文，不修改个人配置；测试窗口不主动获取焦点。快捷键检查短暂创建独立输入钩子，请单独运行桌面测试。

`report.json` 的分配量含测试调用本身，鼠标钩子通过反射调用，不能将其微秒数解释为真实键鼠延迟。会话测试是未变化文件的稳态缓存；变化文件会按需重新读取。`wheel.json` 为展开过程绘图记录，`report.json` 另列稳定展开时的状态动效绘图记录，均不包含 Windows 合成或前台激活延迟。真实进程 CPU / 内存另行采样，运行任务与屏幕活动会影响结果。

行为回归：`CodeManager.exe --task-status-test <report.json>`，包含标题更新、追加记录、会话替换、快捷键原地修改、窗口身份保护及状态批次写入失败重试。
