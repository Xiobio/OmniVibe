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

Add `-- --playback-all` for the final ten-game integration check:

```powershell
dotnet run --project tools/signature-settings-validation/SignatureSettingsValidation.csproj -c Debug -- --playback-all
```

This keeps the nine baseline groups and adds one all-game group. Before any sound
is played, every installed game signature must exist, validate as PCM WAV and
match its verified catalog SHA-256. A missing clip, pending catalog entry or a
user override shadowing the signature fails the check; none is skipped or
replaced with a generated cue. Existing user overrides are never removed.

For each of the ten games, the test saves and reloads an explicit sound-theme
selection in isolated state, then separately saves and reloads follow-interface
mode. Both routes call the real `Manager.PlayCue` through native `GameAudio`
output at 0.1% volume: twenty complete playbacks. The report records selected and
actual paths, source SHA-256, source and decoded frame counts, playback timing and
natural endpoint release. It waits for complete playback rather than using Stop
immediately after the device opens; a prematurely truncated voice fails. This
also requires the device-open to voice-end interval to stay within the nominal
WAV length × 1.25 + 100 ms, so an underrunning or slowed playback cannot pass just
because it eventually finishes. Per-playback timelines are retained in
`artifacts/signature-settings-validation/playback-all/`, including failed attempts.
The extra observation period on a timeout measures the actual completion time;
it does not relax the success deadline. The report includes the product assembly
SHA-256 to identify the runtime under test. This
verifies source routing and native playback, not a microphone recording or a
subjective listening assessment. No Manager constructor, hooks or terminal
operations run. Hash guards also check real task files and stable/preview
Terminal settings before and after; only hashes enter the report.
