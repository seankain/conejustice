#!/usr/bin/env python3
"""Synthesises the game's placeholder sound effects.

These are generated, not sourced, so there is no third-party licence attached
to any of them: they belong to this project like the code does. They exist so
the audio wiring is testable end to end. Replace them with real recordings when
there are some, keeping the filenames, and nothing in the game has to change.

Deterministic: reseeded per file, so regenerating gives byte-identical output.

    python3 Tools/generate_placeholder_audio.py Assets/Audio
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 22050


def _env(n, attack, decay, floor=0.0):
    """Attack/decay envelope, both given as a fraction of the whole sound."""
    a = max(int(n * attack), 1)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / max(n - a, 1)
            out.append(max((1.0 - t) ** (1.0 / max(decay, 0.01)), floor))
    return out


def _lowpass(samples, cutoff_start, cutoff_end):
    """One-pole lowpass with a cutoff that sweeps, for whoosh and thud shaping."""
    out = []
    y = 0.0
    n = len(samples)
    for i, s in enumerate(samples):
        cutoff = cutoff_start + (cutoff_end - cutoff_start) * (i / max(n - 1, 1))
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
        y += alpha * (s - y)
        out.append(y)
    return out


def _noise(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def _tone(n, freq, shape="sine", detune=0.0):
    out = []
    for i in range(n):
        p = (freq + detune * i / n) * i / RATE
        if shape == "sine":
            out.append(math.sin(2.0 * math.pi * p))
        elif shape == "square":
            out.append(1.0 if (p % 1.0) < 0.5 else -1.0)
        else:  # saw
            out.append(2.0 * (p % 1.0) - 1.0)
    return out


def _ping(n, freq, decay=14.0):
    """A struck resonance: sine under a sharp exponential decay."""
    return [math.sin(2.0 * math.pi * freq * i / RATE) * math.exp(-decay * i / n)
            for i in range(n)]


def _mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def _apply(samples, envelope):
    return [s * e for s, e in zip(samples, envelope)]


def _seq(notes, shape="square", gap=0.0):
    """Ascending or descending note run."""
    out = []
    for freq, dur in notes:
        n = int(RATE * dur)
        out.extend(_apply(_tone(n, freq, shape), _env(n, 0.04, 0.5)))
        out.extend([0.0] * int(RATE * gap))
    return out


def _normalise(samples, peak=0.8):
    high = max(abs(s) for s in samples) or 1.0
    return [s / high * peak for s in samples]


def _write(path, samples):
    samples = _normalise(samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    return len(samples) / RATE


def throw_whoosh():
    n = int(RATE * 0.28)
    return _apply(_lowpass(_noise(n), 4000, 700), _env(n, 0.12, 0.45))


def cone_car():
    # Bright and hollow: what a plastic cone does to sheet metal.
    n = int(RATE * 0.18)
    return _mix(_apply(_lowpass(_noise(n), 6000, 2500), _env(n, 0.01, 0.2)),
                [s * 0.7 for s in _ping(n, 940)],
                [s * 0.4 for s in _ping(n, 1490, 20.0)])


def cone_ground():
    # Duller and shorter: tarmac absorbs where a panel rings.
    n = int(RATE * 0.16)
    return _mix(_apply(_lowpass(_noise(n), 1800, 350), _env(n, 0.01, 0.25)),
                [s * 0.5 for s in _ping(n, 230, 22.0)])


def cone_settled():
    n = int(RATE * 0.11)
    return _seq([(680, 0.055), (1020, 0.055)], "sine")


def car_coned():
    return _seq([(523, 0.10), (659, 0.10), (784, 0.20)], "square")


def reload_rustle():
    # Long enough to cover the default 0.9s lockout; SfxPlayer repitches it if
    # reload_time is changed, so it always ends when throwing comes back.
    n = int(RATE * 0.9)
    base = _lowpass(_noise(n), 2600, 900)
    wobble = [0.45 + 0.55 * abs(math.sin(2.0 * math.pi * 5.5 * i / RATE)) for i in range(n)]
    clunks = [0.0] * n
    for at in (0.04, 0.42, 0.78):
        start = int(RATE * at)
        for i, s in enumerate(_ping(int(RATE * 0.05), 320, 25.0)):
            if start + i < n:
                clunks[start + i] += s * 0.6
    return _mix(_apply(_apply(base, wobble), _env(n, 0.05, 0.8, 0.25)), clunks)


def empty_click():
    n = int(RATE * 0.06)
    return _apply(_lowpass(_noise(n), 7000, 3000), _env(n, 0.004, 0.12))


def low_time_beep():
    n = int(RATE * 0.12)
    return _apply(_tone(n, 880, "square"), _env(n, 0.06, 0.5))


def section_clear():
    return _seq([(523, 0.11), (659, 0.11), (784, 0.11), (1047, 0.28)], "square")


def time_up():
    n = int(RATE * 0.7)
    return _apply(_tone(n, 400, "saw", detune=-280), _env(n, 0.02, 0.7))


SOUNDS = {
    "throw_whoosh": throw_whoosh,
    "cone_car": cone_car,
    "cone_ground": cone_ground,
    "cone_settled": cone_settled,
    "car_coned": car_coned,
    "reload_rustle": reload_rustle,
    "empty_click": empty_click,
    "low_time_beep": low_time_beep,
    "section_clear": section_clear,
    "time_up": time_up,
}

if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "Assets/Audio"
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, fn in SOUNDS.items():
        random.seed(name)          # per-file seed keeps regeneration stable
        path = os.path.join(out_dir, name + ".wav")
        length = _write(path, fn())
        size = os.path.getsize(path)
        total += size
        print("  %-16s %5.2fs  %6.1f KB" % (name, length, size / 1024.0))
    print("  %-16s        %6.1f KB total" % ("", total / 1024.0))
