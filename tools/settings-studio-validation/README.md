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

The twelve groups also exercise routed recorder input and Escape cancellation,
per-action clear/reset, persisted custom and disabled shortcuts, duplicate and
system-reserved chord errors, and the real Win32 registration lifecycle. A
temporary input service uses uncommon F18/F19 chords to prove that custom task
keys and the visibility key are released while settings are open. All temporary
hooks and registrations are disposed; no physical keystrokes are sent.

The guide is checked against customized/disabled keys and paused input, with
working add/recovery/settings actions and fresh-install-only startup behavior.
Visual loadout drafts preserve task identities and survive reopening without
changing live equipment. All five settings pages retain usable footer actions
at 720×580. The thirteen image choices are selected by clicking their cards;
there is no duplicate text dropdown.

Terminal previews use the shipped background images/animations. Native preview
scenes illustrate component layout and palette; they are not live task captures.
