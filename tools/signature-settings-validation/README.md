# Window-switch sound preferences regression

Run from the repository root:

```powershell
dotnet run --project tools/signature-settings-validation/SignatureSettingsValidation.csproj -c Debug
```

The production assembly is built to an isolated artifact directory. The test loads
the actual WPF styles and audio panel without constructing the product Manager,
installing hooks, operating a terminal, or changing real task settings. A single
offscreen, nonactivating fixture tests real visibility changes. Saved preferences
use a fresh artifact directory; existing per-theme sound override hashes are
checked before and after. Import and reset drafts are checked without committing
to real theme files. Atomic import rollback remains covered by the isolated random
identity fixtures in `tools/experience-audit/AfterAudit.cs`.

Evidence: `artifacts/signature-settings-validation/report.json` and
`single-signature-settings.png`.

Add `-- --playback` to also exercise the saved explicit/follow selections through
the actual `Manager.PlayCue` and native audio output at 0.1% volume. This requires
the local Heartsteel and VALORANT signature packs. The Manager is allocated without
its constructor, so no tray, hooks, timers, terminal operations or real state save
are started. The report records the actual paths and complete sample lengths.
