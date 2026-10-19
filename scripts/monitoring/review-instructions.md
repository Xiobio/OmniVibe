# OmniVibe 十套皮肤持续巡检

## 已授权的任务

用户要求定期检查另一个 agent 的十套皮肤开发进度，把关键进展发给用户本人的 Lark，并推动开发 agent 在范围内持续优化。用户暂时离开，明确要求后续不要提问。

默认每 15 分钟检查一次。只向 runtime config 中验证过的本人 open_id 发消息，使用 lark-im 技能的 bot 身份。该收件人、进度汇报内容和持续发送意图已获用户授权，无需再次确认。不要发送给群或其他人。

## 运行位置和分工

- 实际项目：`D:\tools\OmniVibe`。会话历史 cwd 仍可能是旧的 `D:\tools\codemanager`；所有项目命令显式指定实际目录。
- 本地配置：`artifacts/skin-monitor/config.json`；其中记录监督会话、开发会话、已验证收件人和可执行文件路径，不包含密钥。
- 上次审查：`artifacts/skin-monitor/review-state.json` 和 `latest-review.md`。
- 开发 agent 可写：`artifacts/skin-monitor/worker-status.json`，包含 completed、in_progress、next_actions、blockers、validation 和 updated_at。
- 监督只读核心实现，维护巡检文件与运行结果；不要与开发者同时修改皮肤和窗口代码，不在其编译期间另起一次同目录构建。

## 每轮审查

1. 读取上次审查及最新开发状态；用 `scripts/monitoring/codex_rpc.py` 的 `CodexRpc` 查询开发会话 `thread/read` 与最新 `thread/turns/list` / `thread/items/list`，确认它在执行、等待还是空闲。
2. 查看 `git status` 和与十套皮肤有关的变更，按 `docs/skin-design-candidates.md` 对照：海克斯枢纽、战术终端、行动协议、冒险装备栏、无间兵器匣、灵蕴法宝匣、星曜指挥台、Agent 备战席、星旅背包、三界百宝袋。
3. 分别检查配置定义、侧栏/总览/设置接入、原创素材、实际预览、任务状态可读性和切换恢复验证。配置定义齐全不代表完整皮肤可用。
4. 使用时间戳与内容哈希识别本轮新证据。检查验证产物是否对应最新源码，区分开发者声称、文件检查结果和本轮亲自验证结果。日志存在不代表验证通过。
5. 新预览产生时实际查看有代表性的图片，检查文字、编号、状态、边距和不同皮肤的区分。不要把未查看图片描述成已通过视觉验收。
6. 构建/自检失败、素材缺失、对比度不足、共享组件仍锁定单一风格等，转化为具体待办。已有检查有效且代码未变时不重复运行昂贵测试。
7. 仅在新增可用皮肤、明显接入进展、验证从失败变通过、重要阻塞、监督故障或全部验收完成时发 Lark。无关键变化则仅记录本地结果，不刷屏。不虚构百分比；每条汇报包含已确认事实、剩余工作、下一步，保持简短。

## 推动持续优化

- 开发会话 active 时保持其运行，不重复排队“继续”消息，不中断或抢占。
- 开发会话 idle 且仍有明确未完成项时，通过 `thread/queue/list` 检查已有队列；已有用户消息优先，不重复创建任务。
- 无待处理消息时，向同一个开发会话 `thread/queue/add` 提交具体修复/验证任务，再 `thread/queue/start`。不要创建新的独立实现代理或更换模型、权限配置。
- notLoaded 时可先 `thread/resume`（excludeTurns=true），保留原有模型与权限；若在另一实例运行或遇到锁则等待后续重试，不强行解锁。
- 无法处理的真实阻塞要明确汇报；不要替用户回答认证、凭据、付费或其他确实需要其参与的事项。
- 若同一故障重复，按证据调整检查或修复路径，不要反复发送相同指令。
- 用户后续明确暂停/取消时优先遵守。达到全部验收后汇报完成，设置 monitoring_complete=true，不再为了持续工作而制造修改。

## 证据与完成条件

全部十套皮肤都有实际侧栏和总览表现，设置可切换，必要素材可用或有明确回退；五种执行状态、空槽、选中、未读和断连可读；关闭装饰仍可操作；换肤不破坏任务绑定/编号/窗口状态；有匹配当前实现的构建、自检和视觉证据。

配套 Terminal 外观属于开发会话当前任务范围，也应核对其配置、可读性、素材路径与验证结果。不要擅自改变用户日常 Terminal 设置。

## Lark 发送与本地记录

按 lark-im 技能发送 Markdown 汇报，使用明确的 bot 身份。收件人和命令路径从 config 读取；用参数数组或 PowerShell 变量传文本，避免 shell 字符串拼接。使用报告内容哈希生成幂等键，发送成功后保存 message_id 与内容哈希。发送失败记录为失败，不声称已送达。

更新 `review-state.json`：last_review_at、worker_status、evidence、remaining、last_sent_message_id、last_sent_hash、monitoring_complete。可扩展字段，保留已有信息；使用临时文件加原子替换。将本轮可读摘要写到 `latest-review.md`。

## 定时任务管理

Windows 任务名：`OmniVibe-Skin-Progress-Review`。脚本每 15 分钟唤醒已有监督会话，监督会话 active 时跳过，避免重叠。

暂停：创建 `artifacts/skin-monitor/STOP`，或运行 `Disable-ScheduledTask -TaskName 'OmniVibe-Skin-Progress-Review'`。

恢复：移除 STOP 文件、按需要将 monitoring_complete 改回 false，再运行 `Enable-ScheduledTask -TaskName 'OmniVibe-Skin-Progress-Review'`。

查看状态：`Get-ScheduledTaskInfo -TaskName 'OmniVibe-Skin-Progress-Review'`；启动/失败日志见 `artifacts/skin-monitor/dispatch-log.jsonl`。

任务使用当前 Windows 用户的交互登录身份，不保存密码。机器需要开机、该用户保持登录，Codex 本地 app-server 和 Lark CLI 需要可用。默认不唤醒休眠机器，错过的运行在系统恢复可用后继续。
