# Theme audio production

Historical synthesis experiment. The daily app no longer plays this 14-event
matrix. Current window feedback is one authentic signature per game; see
[signature packs](../../skins/signature-audio/README.md). `GameAudio` remains the
shared asynchronous PCM playback engine and this material remains useful as
isolated decoder/mixer test fixtures. Legacy quiet/immersive and per-item APIs
below describe that experiment, not the current settings UI.

`python tools/game-audio/generate.py --validate` produces all 182 original,
stereo 44.1 kHz / PCM16 WAV files, the distributed `skins/audio/manifest.json`,
and ignored evidence under `artifacts/game-audio/`. Requires NumPy and SciPy.

The 13 material families use different physical sound recipes (not pitch swaps):
bamboo/jade, dark glass/wind, wood/bronze, crystal/brass gears, spring/receiver,
packet/relay, leather/forged clasp, blade/air, stone/ritual bowl, golden skill
glissando, wooden chess token, celestial harp/glass, and porcelain/flute breath.
Operation arrangements distinguish a draw, latch, release, four-corner array,
backpack reveal, soft hover, and three semantic notification contours.

Peak levels stay below 0.44 before the user's volume; the generated files have
zero endpoints, near-zero DC, no clipping, and short, shaped attacks/releases.
Each semantic operation is RMS-matched across all themes (validated spread below
1 dB) so changing a material family does not unexpectedly double playback level.
They deliberately have no music loop, spoken official line or copied game sample.

Production playback lives in `src/CodeManager/GameAudio.cs`. It uses a bounded
four-voice stereo mixer, 3 × 256-frame WinMM buffers, notification ducking,
per-action debounce and no deferred navigation playback. API calls never read
audio files or wait for audio playback on the UI thread. Warm sample cache is
bounded, custom files are revalidated on timestamp/length changes. Stop/mute
cancels requests and wakes the worker to reset and release native output.
An idle endpoint is released after 800 ms; the worker then sleeps on an event.

`Configure(false)` is authoritative: per-action `Play(..., enabled: true)` cannot
undo master mute. Explicit `Preview` can audition while ordinary audio is muted.
Quiet mode plays only switch/capture/remove and waiting/ready/error, truncating
feedback to 140/200 ms with a fade, and notifications to 600 ms. Immersive mode
uses all 14 complete cues. Master mute and zero volume discard rather than queue.

Custom WAV overrides resolve in this order:

1. `%LOCALAPPDATA%/CodeManager/Audio/<theme>/<identity>/<cue>.wav`
2. `%LOCALAPPDATA%/CodeManager/Audio/<theme>/<cue>.wav`
3. Distributed original `skins/audio/<theme>/<cue>.wav`

Use `GameAudio.OverrideDirectory` to get the canonical, sanitized identity path;
`ValidateWave` checks a draft without writing; `ImportOverride` validates then
atomically copies on Save. `RemoveOverride` restores that layer. Overrides are
PCM16 mono/stereo, 16–96 kHz, 0.01–3 seconds, maximum 1.2 MB; playback resamples
to 44.1 kHz and shapes the edges. Corrupt/missing custom data falls back safely.
Official character lines are not bundled. Users may import recordings they have
permission to use. A per-item voice override can therefore accompany a character
without confusing the framework's functional task ID with its visual identity.
`PreviewFile` auditions an unsaved draft through the same mixer without importing;
`PreviewBuiltIn` explicitly auditions the distributed default without overrides.
Read size is checked on the same file handle before allocating PCM input memory.

Validation: `dotnet run --project tools/game-audio-validation -c Debug -- artifacts/game-audio`.
This compiles the production engine against a minimal skin-contract fixture so
parallel WPF UI edits cannot block it. It exercises all files, malformed WAV,
import/fallback/reset, real native output (almost silent), 1,000 nonblocking calls,
bounded mixing, master mute, quiet mode, audition, immediate Stop, idle release,
and shutdown. It changes no task bindings or terminal configuration.
