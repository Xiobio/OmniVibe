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

**Download the development preview: [Windows x64 · v0.1.1-preview](https://github.com/Xiobio/OmniVibe/releases/tag/v0.1.1-preview)**. Extract the complete archive and run `CodeManager.exe`. Requires .NET 10 Windows Desktop Runtime x64. See [installation and known limits](docs/project-kit/INSTALL.md).

This is a development preview. Building from source requires **Windows and the .NET 10 SDK**. See [global.json](global.json) for the SDK baseline.

```powershell
git clone https://github.com/Xiobio/OmniVibe.git
cd OmniVibe
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

The script builds and launches the app, requesting a normal exit of an existing manager first. **Fresh settings default to Relic. Existing theme choices and task bindings are preserved.**

For preview packages, see the [runtime, installation, update and rollback guide](docs/project-kit/INSTALL.md).

**Language:** right-click the launcher → Settings → General → **Language** → English. Save and restart. The default follows your system language; non-Chinese systems use English. [See the English UI and language guide](docs/localization/README.md). To override it for one launch:

```powershell
.\src\CodeManager\bin\Debug\net10.0-windows\CodeManager.exe --language=en
```

Exit the existing manager first when launching with a language override.

| Default shortcut | Action |
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
