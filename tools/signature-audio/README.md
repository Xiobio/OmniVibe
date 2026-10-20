# Real game signature audio

This workflow replaces procedural theme imitations with **one sourced signature
per game**. It does not produce fourteen action variations, music loops, voice
clones or synthetic substitutes. A missing original stays explicitly missing.

The distributable repository contains only a source catalog and installer.
Copyrighted source files and converted WAVs are kept in ignored `artifacts/`
and `%LOCALAPPDATA%/CodeManager/SignatureAudio/<slug>/signature.wav`. Existing
custom action/character audio under `CodeManager/Audio/` is not touched.

```
python tools/signature-audio/install.py
python tools/signature-audio/install.py --slug hextech
python tools/signature-audio/install.py --ffmpeg C:/tools/ffmpeg.exe
python tools/signature-audio/validate.py
```

Requires Python and an existing FFmpeg binary (PATH, explicit argument, or an
already installed `imageio_ffmpeg`). The script installs nothing globally and
never plays through the speakers. Downloads are capped at 2 MB per clip and
validated against exact source SHA-256. Original game dynamics, pitch and timbre
are retained: conversion only resamples to PCM16 stereo 44.1 kHz, trims to at
most three seconds, applies a tiny edge fade, and **attenuates only if needed**
to avoid decoder overshoot. No RMS/loudness normalization, compression, layering,
EQ, or re-synthesis is applied.

An existing differing signature is preserved unless `--replace` is explicitly
passed. Existing files are preserved before any network request or FFmpeg lookup,
so ordinary installation still succeeds with an offline source host. Preservation
does not certify a user-modified file; run `validate.py` to check the cache.
If original download artifacts were removed, use `validate.py --cache-only`:
this checks the installed WAV and its provenance receipt without claiming to
have rechecked absent original source bytes.
Each installed file has `signature.source.json` next to it, recording
the source, third-party origin, precise time range, processing command and hash.
The original audio remains the property of the relevant game rights holders;
community hosting and public download are not claims of CC0 or blanket
redistribution rights. The catalog distinguishes wiki game assets, official
promotional game assets and community game recordings.

Current delivery: eight installed signatures and two explicitly missing games
(Dungeon Fighter Online and Golden Spatula). The Fantasy Westward Journey cue
is the official **web game** battle-victory sound (`BATTLE_WIN` / `ui_shengli`),
verified against its public game configuration and CDN resource table; it is
not claimed to come from the desktop client. The Naraka
clip is the official **mobile promotional game** parry sound; it is not claimed
to be the same file as the desktop client. The Honor of Kings signature is a
complete 1.49-second official Li Bai skill voice, identified by the official
hero JSON. Genshin's attribution is from a community sound page, not a client
bank manifest.

A fresh-download check currently gets HTTP 403 for the two Fandom CDN sources
(Heartsteel and VALORANT). Their earlier downloaded, checksum-verified copies
and installed WAVs work locally. The other six sources were downloaded again
and converted identically. The installer records each failed source and continues
the remaining games, then exits with code 1 if any download/conversion failed.
It does not report a partial reinstall as success or attempt to bypass access
restrictions. Existing valid source files can be retained in `--work-dir` for
offline reinstallation.
