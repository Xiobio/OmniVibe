"""Original music bed and sound design for the OmniVibe promo.

Everything is synthesized here, except the short status chime, which is the
project's own CC0 VCSL completion sound. Output: 48 kHz stereo WAV.
Usage: python music.py <timeline.json> <repo root> <out.wav>
"""
import json
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 48000
rng = np.random.default_rng(7)


def note(n):  # MIDI → Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def env(length, attack, release, sustain=1.0):
    t = np.arange(length) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((length / SR - t) / max(release, 1e-4), 0, 1)
    return a * r * sustain


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, min(cutoff, SR / 2 - 100), 'low', fs=SR, output='sos'), x)


def highpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, 'high', fs=SR, output='sos'), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], 'band', fs=SR, output='sos'), x)


def saw(freq, length, detune=0.0):
    t = np.arange(length) / SR
    phase = (freq * (1 + detune) * t + rng.random()) % 1.0
    return 2 * phase - 1


class Mix:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buses = {k: np.zeros((self.n, 2)) for k in ('drums', 'bass', 'pad', 'lead', 'fx', 'sfx')}

    def add(self, bus, at, sig, gain=1.0, pan=0.0):
        start = int(at * SR)
        if start >= self.n:
            return
        if sig.ndim == 1:
            left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            sig = np.stack([sig * left, sig * right], axis=1) * np.sqrt(2)
        end = min(self.n, start + len(sig))
        self.buses[bus][start:end] += sig[:end - start] * gain


# ---------- instruments ----------
def kick():
    n = int(.45 * SR); t = np.arange(n) / SR
    f = 46 + 90 * np.exp(-t * 28)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5)
    click = highpass(rng.standard_normal(n), 2500) * np.exp(-t * 180) * .25
    return np.tanh((body + click) * 1.6) * .9


def clap():
    n = int(.35 * SR); t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 900, 6000)
    e = np.exp(-t * 18) + .6 * np.exp(-((t - .012) ** 2) / 1e-5) + .5 * np.exp(-((t - .024) ** 2) / 1e-5)
    return noise * e * .35


def hat(open_=False):
    n = int((.32 if open_ else .07) * SR); t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 7000, 4) * np.exp(-t * (9 if open_ else 70)) * .22


def bass(midi, seconds):
    n = int(seconds * SR)
    x = saw(note(midi), n) + .5 * np.sin(2 * np.pi * note(midi - 12) * np.arange(n) / SR)
    x = lowpass(x, 380) * env(n, .01, .12)
    return np.tanh(x * 1.4) * .5


def pad(midis, seconds, cutoff=1600, attack=.9, release=1.2):
    n = int(seconds * SR); out = np.zeros((n, 2))
    for m in midis:
        for d, p in ((-.004, -.6), (0, 0), (.0045, .6)):
            s = lowpass(saw(note(m), n, d), cutoff)
            out[:, 0] += s * np.cos((p + 1) * np.pi / 4); out[:, 1] += s * np.sin((p + 1) * np.pi / 4)
    return out * env(n, attack, release)[:, None] * (.11 / len(midis) ** .5)


def pluck(midi, seconds=.9, bright=.5):
    """Karplus–Strong string for the arpeggio."""
    n = int(seconds * SR); period = int(SR / note(midi))
    buf = rng.uniform(-1, 1, period); out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = .5 * (buf[i % period] + buf[(i + 1) % period]) * (.994 + bright * .005)
    return lowpass(out, 5200) * env(n, .002, .3) * .5


PLUCK_CACHE = {}


def cached_pluck(midi, bright=.5):
    key = (midi, bright)
    if key not in PLUCK_CACHE:
        PLUCK_CACHE[key] = pluck(midi, bright=bright)
    return PLUCK_CACHE[key]


def bell(midi, seconds=2.5):
    n = int(seconds * SR); t = np.arange(n) / SR; f = note(midi)
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for a, r, d in ((1, 1, 1.6), (.5, 2.76, 3.2), (.25, 5.4, 6), (.15, 8.9, 9)))
    return x * .18


def riser(seconds, f0=300, f1=6000):
    n = int(seconds * SR); t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n); chunk = 2048
    for i in range(0, n, chunk):
        c = f0 * (f1 / f0) ** (i / n)
        out[i:i + chunk] = bandpass(noise[i:i + chunk], c * .7, min(c * 1.4, SR / 2 - 200))
    tone = np.sin(2 * np.pi * np.cumsum(220 * 2 ** (2 * t / seconds)) / SR) * .25
    return (out * .5 + tone) * (t / seconds) ** 2 * .5


def reverse_swell(seconds):
    n = int(seconds * SR); t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 3000) * (t / seconds) ** 3 * .35


def boom(seconds=3.0):
    n = int(seconds * SR); t = np.arange(n) / SR
    f = 38 + 60 * np.exp(-t * 6)
    low = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.6)
    noise = lowpass(rng.standard_normal(n), 900) * np.exp(-t * 4) * .4
    return np.tanh((low + noise) * 1.3) * .9


def whoosh(seconds=.6, up=True):
    n = int(seconds * SR); t = np.arange(n) / SR
    noise = rng.standard_normal(n); out = np.zeros(n); chunk = 1024
    for i in range(0, n, chunk):
        k = i / n; c = 400 + (5000 if up else 3000) * (k if up else 1 - k)
        out[i:i + chunk] = bandpass(noise[i:i + chunk], c * .6, c * 1.6)
    return out * np.sin(np.pi * t / seconds) ** 2 * .45


def tick(freq=1800, seconds=.05):
    n = int(seconds * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t) * np.exp(-t * 90) * .35


def key_click():
    n = int(.06 * SR); t = np.arange(n) / SR
    return (bandpass(rng.standard_normal(n), 1500, 9000) * np.exp(-t * 140) + np.sin(2 * np.pi * 420 * t) * np.exp(-t * 60) * .3) * .5


def read_wav(path):
    with wave.open(str(path)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float) / 32768
        ch, rate = w.getnchannels(), w.getframerate()
    data = data.reshape(-1, ch).mean(axis=1)
    if rate != SR:
        x = np.arange(0, len(data), rate / SR); data = np.interp(x, np.arange(len(data)), data)
    return data


def reverb_ir(seconds=2.6):
    n = int(seconds * SR); t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t * 3.2)[:, None]
    ir[:, 0] = lowpass(ir[:, 0], 7000); ir[:, 1] = lowpass(ir[:, 1], 7000)
    return ir / np.abs(ir).sum(axis=0) * 6


def main():
    timeline = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    root = Path(sys.argv[2]); out = Path(sys.argv[3])
    ev = timeline['events']; beat = 60 / timeline['bpm']; total = timeline['duration']
    m = Mix(total + 3)

    # Chords (D minor): i – VI – III – VII.
    prog = [[50, 57, 62, 65], [46, 53, 58, 62], [53, 57, 60, 65], [48, 55, 60, 64]]
    roots = [38, 34, 41, 36]

    # ---- Intro 0–6 s: drone, heartbeat, ticking.
    m.add('pad', 0, pad([38, 45, 50], 6.6, cutoff=700, attack=2.2, release=1.5), 1.2)
    for b in range(0, 10, 2):
        m.add('drums', b * beat, kick(), .45)
    for k in range(20):
        m.add('drums', k * beat / 2, hat(), .25 + .02 * k, pan=.3)
    for t in ev['windowPops']:
        m.add('sfx', t, tick(1500 + rng.integers(0, 700)), .5, pan=float(rng.uniform(-.6, .6)))
    m.add('sfx', ev['waitingChip'], read_wav(root / 'skins/completion-audio/midnight/complete.wav'), .55)

    # ---- Alt-Tab 6–9 s: tension.
    for k in range(24):
        m.add('drums', 6 + k * beat / 4, hat(), .3 + k * .012, pan=-.2)
    m.add('fx', 6.0, riser(3.0), .9)
    m.add('pad', 6.0, pad([38, 44, 50], 3.2, cutoff=900, attack=.5, release=.4), 1.0)
    for t in ev['altTab']:
        m.add('sfx', t, key_click(), .9, pan=.1)
    m.add('fx', ev['brandImpact'] - .9, reverse_swell(.9), 1.0)

    # ---- Brand 9–13.2 s: impact, bright Bb chord, bells.
    t0 = ev['brandImpact']
    m.add('drums', t0, boom(), 1.0)
    m.add('pad', t0, pad([46, 53, 58, 62, 65], 4.6, cutoff=2600, attack=.05, release=1.6), 1.5)
    for k, n_ in enumerate([74, 77, 81, 86]):
        m.add('lead', t0 + .3 + k * .32, bell(n_), .7, pan=-.4 + k * .25)
    m.add('sfx', t0 - .35, whoosh(.5), .8)

    # ---- Main groove 13.2–43.2 s, lift 43.2–52.8 s.
    groove_start, lift_start, outro = timeline['scenes']['capture'][0], timeline['scenes']['themes'][0], timeline['scenes']['cta'][0]
    bar = 4 * beat
    t = groove_start; bar_index = 0
    while t < outro - 1e-6:
        chord = prog[(bar_index // 2) % 4]; low = roots[(bar_index // 2) % 4]
        lift = t >= lift_start
        if bar_index % 2 == 0:
            m.add('pad', t, pad(chord, 2 * bar + .6, cutoff=2400 if lift else 1700, attack=.4, release=.8), 1.0)
        for b in range(4):
            bt = t + b * beat
            m.add('drums', bt, kick(), .8 if b in (0, 2) else 0)
            if b in (1, 3):
                m.add('drums', bt, clap(), .7)
            m.add('drums', bt + beat / 2, hat(open_=lift and b == 3), .55 if lift else .4, pan=.25)
            m.add('drums', bt, hat(), .25, pan=-.25)
            m.add('bass', bt, bass(low, beat * .9), .9)
            m.add('bass', bt + beat / 2, bass(low + (12 if b == 3 else 0), beat * .45), .55)
        arp = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[3] + 12, chord[2] + 12, chord[1] + 12, chord[3] + 12, chord[2] + 24]
        for k in range(16):
            n_ = arp[k % 8] + (12 if lift and k % 4 == 3 else 0)
            m.add('lead', t + k * beat / 4, cached_pluck(n_, .9 if lift else .5), .5 if lift else .38, pan=-.35 if k % 2 else .35)
        t += bar; bar_index += 1

    # Scene accents.
    for k, c in enumerate(ev['captures']):
        m.add('sfx', c - .32, whoosh(.45), .55, pan=.4)
        m.add('sfx', c, tick(2400 + 120 * k, .08), .7, pan=.3)
    m.add('sfx', ev['hover2'], tick(2000), .5); m.add('sfx', ev['hover3'], tick(2200), .5)
    chime = read_wav(root / 'skins/completion-audio/relic/complete.wav')
    m.add('sfx', ev['switchConfirm'], chime, .6)
    m.add('sfx', ev['radialStart'], whoosh(.5, up=False), .45)
    for s in ev['radialSelect']:
        m.add('sfx', s, tick(1900), .55)
    m.add('sfx', ev['radialRelease'], chime, .5)
    m.add('sfx', ev['tabKey'], key_click(), .9)
    m.add('sfx', ev['tabKey'] + .15, whoosh(.5), .4)
    m.add('sfx', ev['waitingFocus'], read_wav(root / 'skins/completion-audio/ink-jade/complete.wav'), .55)
    m.add('sfx', ev['arrangeKey'], key_click(), .9); m.add('sfx', ev['arrangeGrid'], whoosh(.7), .6)
    m.add('sfx', ev['restoreKey'], key_click(), .9); m.add('sfx', ev['restoreGrid'], whoosh(.7, up=False), .5)
    m.add('fx', lift_start - 2.4, riser(2.4, 500, 8000), .6)
    for c in ev['themeCuts'][1:]:
        m.add('sfx', c - .2, whoosh(.35), .35, pan=float(rng.uniform(-.5, .5)))

    # ---- Outro 52.8–60 s: logo hit and resolving chord.
    m.add('fx', outro - .9, reverse_swell(.9), 1.0)
    m.add('drums', outro, boom(4.0), .85)
    m.add('pad', outro, pad([38, 45, 50, 57, 64, 69], 7.6, cutoff=2200, attack=.08, release=4.0), 1.6)
    for k, n_ in enumerate([69, 74, 76, 81]):
        m.add('lead', outro + .25 + k * .45, bell(n_, 3.5), .6, pan=-.3 + k * .2)

    # ---- Bus processing and master.
    ir = reverb_ir()
    def verb(x, amount):
        wet = np.stack([fftconvolve(x[:, c], ir[:, c])[:len(x)] for c in range(2)], axis=1)
        return x + wet * amount
    bus = m.buses
    master = (verb(bus['pad'], .5) * 1.5 + verb(bus['lead'], .45) * 1.35 + bus['bass'] * .55 +
              verb(bus['drums'], .12) * .62 + verb(bus['fx'], .3) + verb(bus['sfx'], .2) * 1.1)
    master = master[:int(total * SR)]
    n = len(master); t = np.arange(n) / SR
    fade = np.clip((total - t) / 1.8, 0, 1) ** 1.5 * np.clip(t / .05, 0, 1)
    master *= fade[:, None]
    peak = np.abs(master).max(); master = np.tanh(master / peak * 1.25) * .89
    pcm = (master * 32767).astype(np.int16)
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    print('wrote', out, round(n / SR, 2), 's')


if __name__ == '__main__':
    main()
