# Install, update and recover / 安装、更新与恢复

## Development preview / 开发预览

Some features and interactions are still incomplete. Use a preview build with recoverable work and report reproducible issues. The application manages whole windows, not individual Terminal tabs.

部分功能与交互仍在完善，建议先用可恢复的测试任务体验。程序管理整个窗口，不单独管理 Terminal 标签页。

## Requirements / 环境要求

- Windows desktop, x64 for the `win-x64` package.
- **.NET 10 Windows Desktop Runtime, x64** for framework-dependent packages. The SDK is only needed to build from source. The base .NET Runtime alone is insufficient for this WPF application.
- Windows Terminal is needed for Terminal-specific appearance integration.

框架依赖包需要 **.NET 10 Windows Desktop Runtime x64**，不是仅安装基础 .NET Runtime；从源码编译才需要 SDK。终端外观集成需要 Windows Terminal。

## First launch / 首次启动

1. Check the ZIP's SHA-256 against `SHA256SUMS.txt` with `Get-FileHash .\OmniVibe-*.zip -Algorithm SHA256`.
2. Extract the entire archive into a writable folder. Keep `skins`, `themes`, scripts and DLLs together with `CodeManager.exe`.
3. Run `CodeManager.exe` as a regular user. The launcher and hamster tray icon provide access.
4. Bind one test terminal first. Try switching and restoring it, then add your other windows.

校验压缩包后完整解压，勿仅复制 EXE。普通权限运行 `CodeManager.exe`，先用一个测试终端验证绑定、切换和恢复，再加入其他任务。不要通过关闭系统安全功能来解决启动问题。

If a runtime is missing, install the matching Windows Desktop Runtime and retry. A currently running instance must exit normally before starting another build. Language can be selected in Settings → General; save and restart.

缺少运行库时安装匹配版本；已运行的实例须从托盘正常退出后再启动另一版本。设置 → 通用可切换语言，保存后重启。

## Update and rollback / 更新与回退

1. Exit OmniVibe from its tray menu so it restores managed windows.
2. Back up `%LOCALAPPDATA%\CodeManager` privately. It can contain task names, window titles, paths and session metadata.
3. Keep the previous application folder. Extract the new version to a separate folder and run it.
4. If the update fails, exit it normally and start the previous version. If configuration compatibility is the problem, restore your saved configuration while OmniVibe is stopped.

从托盘正常退出，私下备份 `%LOCALAPPDATA%\CodeManager`，保留旧版目录，新版解压至另一目录。回退时先退出新版，再启动旧版；必要时在程序停止状态下恢复备份配置。不要将个人配置或完整日志上传到公开 Issue。

Terminal appearance changes use their own configuration backups. Restore through the appearance tooling or the recorded backup; restoring OmniVibe task settings alone does not undo Windows Terminal settings.

终端外观使用独立的 Terminal 配置备份；恢复任务配置不会自动撤销 Terminal 外观修改。

## Known limits / 已知限制

- Global `Tab` may conflict with terminal completion; change or disable it in Settings.
- Automatic Agent status needs supported CLI events; unknown status does not prevent window management.
- Missing optional theme audio stays silent; theme images do not install audio.
- Language changes require a restart. User data and text in artwork keep their original language.
- Window permissions, display scaling and multiple monitors need testing in your environment.

全局 Tab 可与补全冲突；自动状态需要 CLI 接入；缺少可选音频时静音；语言变更需重启。管理员权限窗口、多显示器和缩放兼容性应按实际环境验证。

## Remove / 移除

Exit normally, undo any Terminal appearance changes you want to remove, then delete the extracted application folder. Keep local task settings if you intend to reinstall; remove them separately only after backing up anything you need.

正常退出，按需恢复 Terminal 外观，再删除解压目录。个人任务数据独立存储，可保留供以后重装使用。
