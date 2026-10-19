# Settings studio validation

Run from the repository root:

```powershell
dotnet run --project tools/settings-studio-validation/SettingsStudioValidation.csproj -c Debug -- artifacts/settings-studio/validation
```

The harness uses the real settings window and WPF resources in its own process,
with synthetic task previews. It checks all 13 choices and five views, draft/save
boundaries, live GIF playback, hidden/unloaded animation cleanup, footer bounds
and scrolling on short windows. It writes screenshots and `report.json` to the
chosen output folder. It neither starts the task manager nor invokes Terminal
appearance application; the live Terminal settings hash must remain unchanged.

Terminal previews use the shipped background images/animations. Native preview
scenes illustrate component layout and palette; they are not live task captures.
