<p align="center"><img src="assets/brand/v4/icons/omnivibe-128.png" width="80" height="80" alt="OmniVibe"></p>
<h1 align="center">OmniVibe</h1>
<p align="center"><strong>Vibe code like you play. Make every window part of your world.</strong><br>
Find your task. Switch in a gesture. Make room to focus.</p>
<p align="center"><a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="docs/project-kit/showcase.en.md">Theme gallery</a> · <a href="docs/project-kit/README.md">Docs</a> · <a href="CONTRIBUTING.md">Contribute</a></p>
<p align="center"><strong>WINDOW MANAGEMENT · GAME-INSPIRED INTERACTION · YOUR OWN STYLE</strong><br><sub>Windows · .NET 10 · Development preview · MIT code</sub></p>

**Ten terminals open. Where did that task go?** You came here to build, but keep cycling through similar titles, dragging windows around, and resizing the same layout.

**OmniVibe turns scattered terminals and AI Agent windows into a fixed task inventory. Switch tasks like you switch characters, gear, or abilities in a game.** A compact launcher expands when you need it. One shortcut arranges your windows. Your favorite portraits, themed artwork, and optional sound effects make the workspace feel like yours.

**Less window hunting. More flow. Make Vibe Coding feel like play.**

> **An evolving development preview.** Core window capture, switching, and arrangement are available, but some features and interactions are still incomplete, and compatibility needs more real-world testing. Try it, report issues, or send a PR—help us make Vibe Coding smoother and more fun. [Current limitations](#what-to-expect) · [Contribute](CONTRIBUTING.md)

## See it in action

https://github.com/user-attachments/assets/15ff02c9-392c-4eed-958c-ab0b1cdb485a

**Default theme: Black Myth: Wukong · Relic Vault.** A coordinated wheel, task inventory, and terminal appearance. Sound follows the selected theme by default; corresponding audio must be installed locally. Missing audio stays silent, and you can import your own WAV files.

<table><tr>
<td align="center"><img src="docs/game-suite-refinement/screens/deck-relic-decorated.png" width="300" alt="Expanded Relic task wheel"><br><strong>Point at a task. Get back into flow.</strong></td>
<td align="center"><img src="docs/game-suite-refinement/screens/inventory-relic.png" width="540" alt="Relic task inventory"><br><strong>Your windows, in one view.</strong></td>
</tr></table>

![Relic terminal appearance](docs/terminal-frame-refinement/relic-regular.png)

<sub>Demo video and screenshots are rendered from native UI components with sample tasks, not a live recording. Some screenshots predate the latest build and show Chinese UI. Game-inspired themes do not imply official affiliation.</sub>

## Spend your time building, not hunting for windows

| The friction | What OmniVibe does |
| --- | --- |
| **Too many windows hiding behind each other** | Organize them into **nine fixed slots** that stay in place |
| **Endless Alt+Tab through similar titles** | Jump by **number, radial selection, or recognizable task portraits** |
| **Arranging code, logs, and tests takes effort** | **Arrange and restore** managed windows with a shortcut: grid, columns, rows, or a main window on the left |
| **An Agent may be waiting for you** | See **window previews and task status** together; automatic status requires CLI event integration |
| **Management panels take up space** | Keep a **compact launcher that expands on hover**, with adjustable themes, sound, and animation |

### Capture → Switch → Arrange → Focus

1. **Give each task a home.** Frontend in slot 1, API in slot 2, tests in slot 3. Select a window from an empty slot, or drag its title bar into the launcher.
2. **Switch with a familiar gesture.** Use `Alt + 1–9`, or hold `Alt + Q`, point at a task, and release. Hover to expand the launcher, hold the left mouse button to move it, and right-click to manage it.
3. **Get the bigger picture.** Open the task inventory for previews. Use `Alt + Backtick` to arrange captured windows, then press it again to restore their layout.

Keep using your existing terminals and CLI tools, including Claude Code and Codex. **Window capture, switching, and arrangement work without status integration.**

## Make the workspace yours

**Your favorite character, animal, or animation-inspired portrait can become a task you recognize at a glance.** Themes coordinate the wheel, inventory, and terminal appearance; custom task images, sound, and animation let you tune the atmosphere.

**Relic is the default, with 12 more themes to explore.** The full gallery is organized by interface module, with original images for a closer look.

### [Explore all 13 themes →](docs/project-kit/showcase.en.md)

## Get started

**macOS native preview:** The native port retains the original transparent launcher, equipment wheel, themed inventory, and loadouts using the existing 13 theme packs, with task launching and resuming, CLI status connections, theme audio, and optional window previews. Run `./scripts/macos/run.sh` on macOS 13+ with a Swift 5.9+ toolchain. Window control requires Accessibility access; previews require macOS 14+ and Screen Recording access. The Mac preview is signed with Apple Development and is not notarized; a formal public release still needs Developer ID signing, notarization, and independent system validation. These Mac changes leave the existing Windows version unchanged. See [macOS development and limitations](docs/macos-development.md).

**Mac launcher:** The clickable core stays at 54 pt and keeps its screen anchor throughout hover expansion and collapse. Only the surrounding equipment deploys. Near a screen edge, the orbit fits inward with a connector back to the fixed core, keeping its slots visible and clickable. Existing expanded-wheel size preferences remain in effect; all 13 themes and 117 equipment images retain their complete artwork at the new scale.

**Mac shortcuts:** Defaults are `Option + 1–9` for tasks, hold `Option + Q` for radial selection, `Option + Backtick` to arrange / restore, and `Option + H` to show / hide the launcher. Settings → Shortcuts lets you record, disable, or reset each action, or choose another preset. Switching presets resets all custom bindings and disabled actions. Saving a binding, disabling, or resetting takes effect immediately; recording pauses OmniVibe's shortcuts, and Esc cancels. Duplicate combinations, Esc, and Command combinations with Q, Tab, or Space are rejected without replacing the existing configuration.

**Mac window behavior:** Switching first hides the management UI. Repeating a task number restores its previous state only when that exact window is frontmost; otherwise it re-enters the task. If a background app such as Lark temporarily exposes no accessible window, explicit switching verifies the original process and exact CG window before waking the app and reconnecting that window. Arrangement first wakes every unavailable window that has not been confirmed closed, and moves windows only after all are verified. Preparation failure or cancellation performs no layout moves, preventing a silent three-to-two reduction. Title-bar capture restores the original position before saving a binding. Balanced layout uses two columns for two windows, two above one full-width lower window for three, and a grid from four onward. Window restrictions can prevent arrangement, with the reason kept visible.

**Mac preferences and recovery:** Save wake behavior, minimize-on-capture, gaps, and interface sizes. `Option + Scroll` cycles connected tasks by default; Accessibility and Input Monitoring are checked before installing the scroll listener. A recovery journal is written before window changes for retry after OmniVibe restarts. Reconnection verifies the stable boot UUID, user and login session, original process, and exact window identity while preserving the task binding; titles are never used to guess a match. Confirmed closed tasks enter a 30-item Recent list: reconnect through an empty slot or an explicit window picker, or explicitly launch / resume with the saved name, equipment, and launch configuration. Manual removal does not archive a task and clears its launch and session association. [Details (Chinese)](docs/macos-development.md#窗口偏好滚轮与恢复).

**Mac launching and sessions:** Save a project directory, executable absolute path, and exact session UUID. Launch first opens a new Terminal window, verifies its new TTY, and persists the task binding before dispatching the command. Configuring a live task only saves settings. CLI resume continues a saved conversation; it does not restore process memory. Local session discovery extracts metadata and allowlisted status fields, with an explicit initial selection; known provider + UUID associations can reconnect automatically. Terminal contents are not read, and conversation bodies are not stored. Actual hooks / notify take priority over session records, preventing late record updates from overwriting them or repeating alerts. [Launching and resuming (Chinese)](docs/macos-development.md#启动与继续任务).

**Mac slot management:** Drag a card's main preview or a wheel task to another slot to insert it there and shift the intervening tasks. The inventory context menu can also move a task directly into an empty slot. Drag a wheel task well outside the wheel, click ×, or use its context menu to remove it from management while keeping the original window open. Equipment, status, unread reminders, and Agent sessions follow the task UUID. Failed operations retain the binding and explain the cause. [Detailed instructions (Chinese)](docs/macos-development.md#调整槽位与移出管理).

**Mac Terminal themes:** Native Terminal appearance is preserved by default; wheel themes do not change it. The optional experimental integration can export 26 complete static `.terminal` profiles: decorated and minimal variants of all 13 themes, including ANSI 16 colors, text / cursor / selection colors, a monospace font, and background artwork. Import them through Terminal's official settings, then inspect and explicitly apply them in OmniVibe. For original profiles that cannot be independently located, automatic backup first creates a native Terminal copy and records a restoration basis; explicitly selecting a complete original export and separate backup profile remains a fallback. Full file backups precede writes, and failed recovery can be retried. Inspection / application requires your Automation consent. Without linking, applying an OmniVibe theme changes only OmniVibe. This machine has recognized all 26 imported profiles. On two live tabs, automatic backup, full Relic theme application, and original-profile restoration have passed read-back verification. The final full apply → restore cycle confirmed both original profiles restored and theme linking disabled. Background artwork can clash with light surfaces in terminal TUIs; the default native appearance is recommended. Animated backgrounds, system window frames, and iTerm linking are unsupported. [Workflow and scope (Chinese)](docs/macos-development.md#apple-terminal-配色).

**Mac appearance and language:** Explicitly generate and link Claude Code's supported `themes/omnivibe.json` format, retaining the original file before writing and refusing to overwrite external changes. Restore the original file when needed; select OmniVibe in Claude's `/theme` menu. Choose System, Simplified Chinese, or English with immediate interface updates. Window previews use low-frequency still captures.

The separate delivery bundle is at `artifacts/macos/delivery/OmniVibe.app`; final automated results are recorded in `validation.log` beside it. GitHub macOS preview validation and Windows CI have both passed. Lark previously rejected a window operation; the current live round successfully arranged all three original windows—two Terminal windows and Lark—and fully restored their original layout, retaining all three bindings. This result does not establish compatibility with other applications or multiple displays. Real CLI lifecycles still require separate validation; Terminal artwork is not the recommended default. [Validation records (Chinese)](docs/macos-development.md#验证).

**Download the development preview: [Windows x64 · v0.1.1-preview](https://github.com/Xiobio/OmniVibe/releases/tag/v0.1.1-preview)**. Extract the complete archive and run `CodeManager.exe`. Requires .NET 10 Windows Desktop Runtime x64. See [installation and known limits](docs/project-kit/INSTALL.md).

The Windows version is a development preview. Building it from source requires **Windows and the .NET 10 SDK**. See [global.json](global.json) for the SDK baseline.

```powershell
git clone https://github.com/Xiobio/OmniVibe.git
cd OmniVibe
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

The script builds and launches the app, requesting a normal exit of an existing manager first. **Fresh settings default to Relic. Existing theme choices and task bindings are preserved.**

For preview packages, see the [runtime, installation, update and rollback guide](docs/project-kit/INSTALL.md).

**Windows language:** right-click the launcher → Settings → General → **Language** → English. Save and restart. The default follows your system language; non-Chinese systems use English. [See the English UI and language guide](docs/localization/README.md). To override it for one launch:

```powershell
.\src\CodeManager\bin\Debug\net10.0-windows\CodeManager.exe --language=en
```

Exit the existing manager first when launching with a language override.

| Windows default shortcut | Action |
| --- | --- |
| `Alt + 1–9` | Open a task; press again to restore its previous window state |
| `Alt + Mouse wheel` | Cycle through tasks |
| Hold `Alt + Q` | Open the wheel; point and release to switch |
| `Tab` | Toggle task inventory |
| `Alt + Backtick` | Arrange / restore captured windows |
| `Ctrl + Alt + Space` | Show / hide the launcher |
| Left-click the tray icon | Show / hide the floating launcher |

The global `Tab` shortcut can interfere with terminal completion. Change or disable it in Settings. **Click the hamster tray icon** to bring back a hidden launcher.

## What to expect

- **Whole-window management:** individual Windows Terminal tabs and split panes are not separate task slots.
- **Event-based status:** automatic status requires CLI integration; “response ready” does not mean the whole project is finished.
- **Personalization:** custom task images and built-in theme settings are available. A complete community skin SDK is still planned.
- **English UI:** menus, settings, and operating hints are localized. Your task names, terminal output, and text embedded in artwork keep their original language.
- **Stack:** C# / WPF / Win32. The executable and source directory still use the name `CodeManager`.

[CLI integration (Chinese)](docs/usage.md) · [Development guide (Chinese)](docs/project-kit/development.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

## Make Vibe Coding more fun

**This tool is still a work in progress, and we'd love to build it with you.** Help fix an interaction, test multiple monitors and display scaling, improve CLI status integration, or contribute translations, documentation, and theme assets with clear rights. You don't need to write code: reproducible bug reports and feedback from your daily workflow are valuable too.

## Support development

<details>
<summary>☕ Buy the author a coffee (Alipay)</summary>

If OmniVibe makes your parallel tasks easier to manage, you can support continued development and maintenance. **Any amount is welcome. Support is entirely optional and does not unlock or restrict any features.**

<a href="docs/support.md"><img src="assets/support/alipay.png" width="280" alt="Alipay QR code for supporting OmniVibe"></a>

[Open the support page and full-size image](docs/support.md). Bug reports, sharing the project, and contributions are also appreciated.

</details>

Original code, scripts, and documentation use the **[MIT License](LICENSE)**. Third-party artwork, characters, trademarks, and audio have separate rights; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). OmniVibe is not officially affiliated with the referenced games or their publishers.
