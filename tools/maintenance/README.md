# 目录维护与精简发布

在项目根目录执行。两个脚本都以自身位置解析仓库路径。

## 清理可再生成的构建副本

```powershell
# 只扫描并生成计划，不删除
powershell -NoProfile -ExecutionPolicy Bypass -File tools/maintenance/Clean-Generated.ps1

# 应用同样的筛选规则，并记录删除明细
powershell -NoProfile -ExecutionPolicy Bypass -File tools/maintenance/Clean-Generated.ps1 -Apply
```

只处理 `artifacts/` 中可识别为纯 CodeManager 构建输出的目录，以及 `tools/<项目>/bin`、`obj`。报告、截图、临时任务配置和源码快照不作为整体删除目标；源码快照内部符合规则的编译输出仍可清理。

保留当前有进程运行的目录、受保护的最新验收构建、巡检目录、`artifacts/publish/`、所有版本化文件和含重解析点的路径。删除前再次检查绝对路径和运行进程。`src/`、`.git/` 不在允许清理的范围内。目录条目不符合纯构建结构时自动跳过。

清理前应结束其他构建和验证任务，避免它们同时写入输出。报告保存在 `artifacts/maintenance/cleanup-*.json`。重建命令见相应工具 README；引用隔离程序集的诊断工具需要先重新构建该程序集。

## 精简发布

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/maintenance/Publish-Lean.ps1
```

发布到新的 `artifacts/publish/<时间-随机 ID>/app/`，附带 `release-manifest.json`。也可传 `-OutputRoot <新的空目录>`；已有非空目录会被拒绝，避免混入旧文件。

使用 `RuntimeAssetsOnly=true` 过滤生成中间图、提示词、验证记录、测试/构建脚本和不再使用的 v3/v4 背景。保留当前 13 套界面素材、117 张配装图、兼容素材、终端静态背景及可选 GIF、JSON 配置、运行脚本和授权说明。开发构建不启用该过滤，仍保留完整测试素材。

输出是依赖 .NET 10 Desktop Runtime 的 Windows 应用目录，并非自包含安装包。资源清单是实际输出的大小与哈希记录，不代表资源授权证明。
