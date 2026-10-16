# Skin feedback validation

Run from the repository root on Windows with the .NET 10 SDK:

```powershell
dotnet run --project tools/feedback-validation/FeedbackValidation.csproj -c Debug -- artifacts/skin-feedback-validation
```

This builds the development source and writes a JSON report, 20 original PCM WAV previews, ten tray-menu renders, ten feedback glyph renders and a contact sheet. It does not change Terminal settings, launch CLI sessions, play audio or start the normal OmniVibe manager.

The probe briefly shows a tiny nonactivating fixture and short transparent effects owned by its own process. It checks SoundPlayer decoding, unique waveforms, bounded levels, smooth endpoints, all ten visual motifs, native NOACTIVATE/click-through styles, unchanged foreground, expired WPF/native-window cleanup, a 60-action burst cap, cancellation, disabled options, detached targets and an injected animation exception. A failure exits nonzero. Audio playback quality remains a listening check; the generated WAV files support that review without automatically playing sounds.

Generated output belongs under ignored `artifacts/`. The harness itself is versioned so validation can be repeated after skin changes.
