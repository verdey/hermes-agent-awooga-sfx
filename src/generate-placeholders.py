#!/usr/bin/env python3
"""Generate synthesized WAV sound effects for all bundled packs.

Uses only Python stdlib (wave, struct, math) — no external dependencies.
Each pack has 5 events: complete, approval, error, startup, tool_done.

Usage:
    python3 generate-placeholders.py          # generate all packs
    python3 generate-placeholders.py --pack awooga-tugboat  # single pack
    python3 generate-placeholders.py --preview               # play after generating
"""

import wave
import struct
import math
import os
import sys

SAMPLE_RATE = 44100
BITS = 16
CHANNELS = 1

# ─── Synthesis primitives ───────────────────────────────────────────

def _env(samples, attack=0.01, decay=0.1, sustain_level=0.7, release=0.05):
    """ADSR envelope applied in-place."""
    n = len(samples)
    a = int(attack * SAMPLE_RATE)
    d = int(decay * SAMPLE_RATE)
    r = int(release * SAMPLE_RATE)
    s = n - a - d - r
    if s < 0:
        s = 0
    for i in range(min(a, n)):
        samples[i] *= i / max(a, 1)
    for i in range(a, min(a + d, n)):
        t = (i - a) / max(d, 1)
        samples[i] *= 1.0 - (1.0 - sustain_level) * t
    for i in range(a + d, min(a + d + s, n)):
        samples[i] *= sustain_level
    for i in range(max(a + d + s, 0), n):
        t = (i - a - d - s) / max(r, 1)
        t = min(t, 1.0)
        samples[i] *= sustain_level * (1.0 - t)
    return samples


def _tone(freq, duration, volume=0.8, attack=0.005, decay=0.1, sustain_level=0.7, release=0.05):
    """Simple sine tone with ADSR."""
    n = int(SAMPLE_RATE * duration)
    samples = [math.sin(2 * math.pi * freq * i / SAMPLE_RATE) for i in range(n)]
    return _env(samples, attack, decay, sustain_level, release)


def _square_tone(freq, duration, volume=0.5, **kw):
    """Square wave tone."""
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        val = 1.0 if math.sin(2 * math.pi * freq * i / SAMPLE_RATE) >= 0 else -1.0
        samples.append(val * volume)
    env_kw = {k: v for k, v in kw.items() if k in ('attack', 'decay', 'sustain_level', 'release')}
    return _env(samples, **env_kw)


def _sweep(f1, f2, duration, volume=0.8, attack=0.01, release=0.05):
    """Frequency sweep from f1 to f2."""
    n = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        phase = 2 * math.pi * (f1 * t + (f2 - f1) * t * t / (2 * duration))
        samples.append(math.sin(phase) * volume)
    release_n = int(release * SAMPLE_RATE)
    for i in range(max(n - release_n, 0), n):
        samples[i] *= (n - i) / max(release_n, 1)
    attack_n = int(attack * SAMPLE_RATE)
    for i in range(min(attack_n, n)):
        samples[i] *= i / max(attack_n, 1)
    return samples


def _multitone(freqs_amps, duration, volume=0.8, attack=0.005, decay=0.1, sustain_level=0.7, release=0.05):
    """Multiple simultaneous tones with relative amplitudes."""
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n
    for freq, amp in freqs_amps:
        for i in range(n):
            samples[i] += amp * math.sin(2 * math.pi * freq * i / SAMPLE_RATE)
    peak = max(abs(s) for s in samples) or 1.0
    samples = [s / peak * volume for s in samples]
    return _env(samples, attack, decay, sustain_level, release)


def _sequence(notes, gap=0.08):
    """Sequence of (samples_list, duration) tuples with gaps."""
    result = []
    for samples, dur in notes:
        result.extend(samples)
        if gap > 0:
            result.extend([0.0] * int(SAMPLE_RATE * gap))
    return result


def _normalize(samples, target=0.9):
    """Normalize to target peak."""
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * target for s in samples]


def _write_wav(path, samples):
    """Write 16-bit mono WAV."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    samples = _normalize(samples)
    with wave.open(path, 'w') as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(BITS // 8)
        wf.setframerate(SAMPLE_RATE)
        data = b''.join(struct.pack('<h', max(-32768, min(32767, int(s * 32767)))) for s in samples)
        wf.writeframes(data)


# ─── Pack: awoooga-tugboat ─────────────────────────────────────────

def gen_awooga_tugboat(outdir):
    """Deep foghorn, rising sweep — AWOOOGA I'm done!"""

    # complete: 220→880Hz rising sweep (the big AWOOOGA)
    _write_wav(os.path.join(outdir, 'complete.wav'),
               _normalize(_sweep(220, 880, 0.9) + [0.0] * int(SAMPLE_RATE * 0.1)))

    # approval: 180Hz sustained horn
    _write_wav(os.path.join(outdir, 'approval.wav'),
               _tone(180, 0.6, attack=0.02, decay=0.15, sustain_level=0.8, release=0.1))

    # error: 200Hz double buzz (two short blasts)
    buzz1 = _tone(200, 0.15, attack=0.005, decay=0.05, sustain_level=0.9, release=0.02)
    buzz2 = _tone(200, 0.15, attack=0.005, decay=0.05, sustain_level=0.9, release=0.02)
    _write_wav(os.path.join(outdir, 'error.wav'),
               _normalize(buzz1 + [0.0] * int(SAMPLE_RATE * 0.1) + buzz2))

    # startup: 330→660→990Hz triplet (foghorn warming up)
    s1 = _sweep(330, 660, 0.25)
    s2 = _sweep(660, 990, 0.25)
    s3 = _tone(990, 0.3, attack=0.02, decay=0.1, sustain_level=0.7, release=0.08)
    _write_wav(os.path.join(outdir, 'startup.wav'),
               _normalize(s1 + s2 + s3))

    # tool_done: 880Hz short blip
    _write_wav(os.path.join(outdir, 'tool_done.wav'),
               _tone(880, 0.12, attack=0.003, decay=0.03, sustain_level=0.8, release=0.04))


# ─── Pack: ricola-horn ──────────────────────────────────────────────

def gen_ricola_horn(outdir):
    """Alpine horn fanfare — RIIIIICOLaaaa!"""

    # complete: Alpine horn motif (G4-E5-C5 ascending fanfare, sustained)
    # G4=392, C5=523, E5=659 — classic alpine horn harmony
    _write_wav(os.path.join(outdir, 'complete.wav'),
               _normalize(
                   _multitone([(392, 0.6), (523, 0.3), (659, 0.1)], 0.5, attack=0.03, decay=0.1, sustain_level=0.9, release=0.15) +
                   [0.0] * int(SAMPLE_RATE * 0.05) +
                   _multitone([(523, 0.7), (659, 0.3)], 0.7, attack=0.02, decay=0.15, sustain_level=0.85, release=0.2)
               ))

    # approval: Short alpine call
    _write_wav(os.path.join(outdir, 'approval.wav'),
               _multitone([(523, 0.6), (659, 0.4)], 0.4, attack=0.02, decay=0.1, sustain_level=0.8, release=0.08))

    # error: Descending minor third (A4 to F#4)
    _write_wav(os.path.join(outdir, 'error.wav'),
               _normalize(
                   _tone(440, 0.15, attack=0.005, decay=0.05, sustain_level=0.9, release=0.02) +
                   [0.0] * int(SAMPLE_RATE * 0.05) +
                   _sweep(440, 370, 0.3)
               ))

    # startup: Three-note alpine fanfare
    _write_wav(os.path.join(outdir, 'startup.wav'),
               _normalize(
                   _tone(392, 0.15, attack=0.01, decay=0.05, sustain_level=0.8, release=0.03) +
                   [0.0] * int(SAMPLE_RATE * 0.05) +
                   _tone(523, 0.15, attack=0.01, decay=0.05, sustain_level=0.8, release=0.03) +
                   [0.0] * int(SAMPLE_RATE * 0.05) +
                   _tone(659, 0.25, attack=0.01, decay=0.08, sustain_level=0.85, release=0.1)
               ))

    # tool_done: Quick chirp
    _write_wav(os.path.join(outdir, 'tool_done.wav'),
               _sweep(659, 784, 0.1))


# ─── Pack: submarine-dive ───────────────────────────────────────────

def gen_submarine_dive(outdir):
    """Low submarine dive horn — DIVE DIVE DIVE"""

    # complete: Low 110Hz dive horn (long, ominous)
    _write_wav(os.path.join(outdir, 'complete.wav'),
               _normalize(
                   _tone(110, 0.4, attack=0.05, decay=0.15, sustain_level=0.9, release=0.1) +
                   [0.0] * int(SAMPLE_RATE * 0.05) +
                   _tone(110, 0.7, attack=0.03, decay=0.2, sustain_level=0.85, release=0.15)
               ))

    # approval: 150Hz sonar ping
    _write_wav(os.path.join(outdir, 'approval.wav'),
               _normalize(
                   _tone(150, 0.08, attack=0.002, decay=0.02, sustain_level=0.9, release=0.04) +
                   [0.0] * int(SAMPLE_RATE * 0.3) +
                   _tone(150, 0.08, attack=0.002, decay=0.02, sustain_level=0.9, release=0.04)
               ))

    # error: 130Hz klaxon (rapid alternation)
    klaxon = []
    for i in range(4):
        klaxon.extend(_tone(130 if i % 2 == 0 else 150, 0.12,
                           attack=0.003, decay=0.02, sustain_level=0.9, release=0.02))
        if i < 3:
            klaxon.extend([0.0] * int(SAMPLE_RATE * 0.03))
    _write_wav(os.path.join(outdir, 'error.wav'), _normalize(klaxon))

    # startup: Two-tone dive alert (low-high)
    _write_wav(os.path.join(outdir, 'startup.wav'),
               _normalize(
                   _tone(110, 0.3, attack=0.03, decay=0.1, sustain_level=0.85, release=0.05) +
                   [0.0] * int(SAMPLE_RATE * 0.08) +
                   _tone(165, 0.35, attack=0.03, decay=0.1, sustain_level=0.85, release=0.08)
               ))

    # tool_done: 440Hz sonar blip
    _write_wav(os.path.join(outdir, 'tool_done.wav'),
               _tone(440, 0.1, attack=0.002, decay=0.02, sustain_level=0.8, release=0.03))


# ─── Pack: 8bit-blip ────────────────────────────────────────────────

def gen_8bit_blip(outdir):
    """Retro arcade bleeps and bloops — LEVEL UP!"""

    # complete: Rising arpeggio C5-E5-G5-C6
    _write_wav(os.path.join(outdir, 'complete.wav'),
               _normalize(
                   _square_tone(523, 0.08, attack=0.002, decay=0.02, sustain_level=0.8, release=0.01) +
                   [0.0] * int(SAMPLE_RATE * 0.03) +
                   _square_tone(659, 0.08, attack=0.002, decay=0.02, sustain_level=0.8, release=0.01) +
                   [0.0] * int(SAMPLE_RATE * 0.03) +
                   _square_tone(784, 0.08, attack=0.002, decay=0.02, sustain_level=0.8, release=0.01) +
                   [0.0] * int(SAMPLE_RATE * 0.03) +
                   _square_tone(1047, 0.2, attack=0.002, decay=0.05, sustain_level=0.85, release=0.05)
               ))

    # approval: 8-bit fanfare
    _write_wav(os.path.join(outdir, 'approval.wav'),
               _normalize(
                   _square_tone(523, 0.06, attack=0.001, decay=0.01, sustain_level=0.8, release=0.01) +
                   _square_tone(659, 0.06, attack=0.001, decay=0.01, sustain_level=0.8, release=0.01) +
                   _square_tone(784, 0.15, attack=0.001, decay=0.03, sustain_level=0.85, release=0.03)
               ))

    # error: Low square buzz
    _write_wav(os.path.join(outdir, 'error.wav'),
               _normalize(
                   _square_tone(131, 0.1, attack=0.001, decay=0.02, sustain_level=0.9, release=0.01) +
                   [0.0] * int(SAMPLE_RATE * 0.04) +
                   _square_tone(131, 0.1, attack=0.001, decay=0.02, sustain_level=0.9, release=0.01)
               ))

    # startup: Power-on jingle (ascending thirds)
    _write_wav(os.path.join(outdir, 'startup.wav'),
               _normalize(
                   _square_tone(262, 0.1, attack=0.002, decay=0.03, sustain_level=0.8, release=0.02) +
                   [0.0] * int(SAMPLE_RATE * 0.04) +
                   _square_tone(330, 0.1, attack=0.002, decay=0.03, sustain_level=0.8, release=0.02) +
                   [0.0] * int(SAMPLE_RATE * 0.04) +
                   _square_tone(392, 0.1, attack=0.002, decay=0.03, sustain_level=0.8, release=0.02) +
                   [0.0] * int(SAMPLE_RATE * 0.04) +
                   _square_tone(523, 0.2, attack=0.002, decay=0.05, sustain_level=0.85, release=0.05)
               ))

    # tool_done: Coin collect blip
    _write_wav(os.path.join(outdir, 'tool_done.wav'),
               _normalize(
                   _square_tone(988, 0.04, attack=0.001, decay=0.01, sustain_level=0.8, release=0.01) +
                   _square_tone(1319, 0.07, attack=0.001, decay=0.02, sustain_level=0.85, release=0.02)
               ))


# ─── Main ───────────────────────────────────────────────────────────

PACKS = {
    'awooga-tugboat': gen_awooga_tugboat,
    'ricola-horn': gen_ricola_horn,
    'submarine-dive': gen_submarine_dive,
    '8bit-blip': gen_8bit_blip,
}

PACK_DESCRIPTIONS = {
    'awooga-tugboat': 'Deep foghorn, rising sweep — AWOOOGA I\'m done!',
    'ricola-horn': 'Alpine horn fanfare — RIIIIICOLaaaa!',
    'submarine-dive': 'Low submarine dive horn — DIVE DIVE DIVE',
    '8bit-blip': 'Retro arcade bleeps and bloops — LEVEL UP!',
}

EVENTS = ['complete', 'approval', 'error', 'startup', 'tool_done']


def write_pack_yaml(outdir, name, description):
    """Write pack.yaml for a sound pack."""
    import yaml  # fallback: write manually if no yaml lib
    lines = [
        f'name: {name}',
        f'version: "1.0.0"',
        f'description: "{description}"',
        f'author: verdey',
        f'license: MIT',
        f'events:',
    ]
    for event in EVENTS:
        lines.append(f'  {event}: {event}.wav')
    lines.append('volume: 0.8')
    lines.append('cooldown_ms: 3000')
    with open(os.path.join(outdir, 'pack.yaml'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


def main():
    preview = '--preview' in sys.argv
    pack_filter = None
    for arg in sys.argv:
        if arg.startswith('--pack='):
            pack_filter = arg.split('=', 1)[1]
        elif arg == '--pack' and sys.argv.index(arg) + 1 < len(sys.argv):
            pack_filter = sys.argv[sys.argv.index(arg) + 1]

    base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'packs')

    for pack_name, gen_fn in PACKS.items():
        if pack_filter and pack_name != pack_filter:
            continue
        outdir = os.path.join(base_dir, pack_name)
        print(f'🔊 Generating pack: {pack_name}')
        gen_fn(outdir)
        write_pack_yaml(outdir, pack_name, PACK_DESCRIPTIONS[pack_name])
        print(f'   ✅ {outdir}/')
        for event in EVENTS:
            wav_path = os.path.join(outdir, f'{event}.wav')
            size_kb = os.path.getsize(wav_path) / 1024 if os.path.exists(wav_path) else 0
            print(f'      {event}.wav ({size_kb:.1f} KB)')
        if preview:
            for event in EVENTS:
                wav_path = os.path.join(outdir, f'{event}.wav')
                print(f'   🔊 Previewing {event}...')
                os.system(f'afplay "{wav_path}" 2>/dev/null || aplay "{wav_path}" 2>/dev/null || echo "(no audio player)"')

    print(f'\n✅ All packs generated in {base_dir}/')


if __name__ == '__main__':
    main()