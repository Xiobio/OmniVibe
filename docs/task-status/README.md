# 轮盘任务状态

收起时显示所有已收纳任务的汇总，执行中有主题色流动标记，回复、确认或异常有持续的待处理数量；展开后，每个槽位直接显示状态文字与光轨。待处理标记保留到进入对应任务、手动标记已查看，或该会话开始下一轮。窗口处在前台本身不再吞掉完成提醒。

状态来源按能够确认的信息接入：

1. **终端原生信号**：读取实时窗口标题里的盲文旋转标记；Windows Terminal 的选中标签若通过辅助功能暴露进度环、铃铛，也会读取。铃铛只表示需要注意，不能证明任务成功。普通任务名称中的“完成”不作为状态。
2. **本地会话记录**：后台增量读取 Codex 和 Claude Code 的生命周期记录。Codex `task_started` / `task_complete`，Claude 的用户消息、明确回合结束或提问等，转换为执行、回复、等待状态。不会因没有输出、CPU 降低或经过固定时间而猜测完成。只保存会话绑定及状态，不复制聊天正文。
3. **精确 hooks**：保留现有会话级 hooks 接入，用于权限确认、失败、结束等精确信号；hooks 提供的 transcript 路径可继续用于后台观察。不会修改全局 CLI 配置或自动信任 hooks。

当前终端标题与本地会话标题唯一、完整对应时会自动连接；已保存的会话 ID 和路径会继续使用。名称重复、改名或自定义宿主无法唯一对应时，在任务菜单选择「连接当前 CLI 会话状态…」，选一次现有会话即可，不需要关闭或重启 CLI。精确权限事件可从同一菜单的 hooks 接入进入。

十三套皮肤均使用自己的运行、等待、完成和错误配色，机械、战术、星轨和水墨材质使用对应的线饰。运行有流动光轨，待处理有呼吸式标记和数量徽记；关闭界面动效仍保留静态文字、颜色和数量。武器与角色立绘不增加包围圆环。

轮询和文件解析在后台执行，状态更新约 1 秒；会话发现每 8 秒缓存一次；单次每文件最多读取 128 KiB，保留未完成的 UTF-8 行。辅助功能探测独立执行，不阻塞会话读取，隐藏轮盘会停止状态动效；没有已连接窗口时不扫描会话。

限制：会话记录格式不是稳定的公开 API；未知格式保持未知，不虚构完成。Windows Terminal 不同版本可能不暴露铃铛的辅助功能元素，此时使用标题与已连接的会话事件。一个 Terminal 窗口包含多个标签或分屏时，窗口信号来自当前选中的标签／面板；每个受管任务应对应独立窗口，或显式连接所需会话。CLI 换成新会话后，如无法唯一辨认，需要重新选择会话。

依据：[Windows Terminal 进度信号](https://learn.microsoft.com/windows/terminal/tutorials/progress-bar-sequences)、[标题来源](https://learn.microsoft.com/windows/terminal/tutorials/tab-title)、[Terminal 标签状态实现](https://github.com/microsoft/terminal/blob/main/src/cascadia/TerminalApp/TabHeaderControl.xaml)、[Codex hooks](https://learn.chatgpt.com/docs/hooks)、[Claude Code hooks](https://code.claude.com/docs/en/hooks)。

验证命令：`CodeManager.exe --task-status-test <report.json>`。包含真实 WPF 状态渲染、逐主题静态／动态比较、截断与部分行、歧义拒绝、状态持久化和已查看／新回合切换。详细交付证据见本目录的 `validation.json`；机器上的原始验证文件与私人会话保持在忽略目录中。
