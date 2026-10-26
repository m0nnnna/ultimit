#!/usr/bin/env python3
"""make-sounds.py - synthesizes the shell's UI blips (shell/UiSounds.qml plays them). Python standard library only.

    python3 assets/sounds/make-sounds.py [OUTDIR]       writes flyout/launcher/notify/lock/unlock .wav next to this script

Each blip is a few short sine notes with a soft attack and an exponential decay, a little second harmonic for
a HUD "ping", 22.05 kHz mono 16-bit, peaking around -14 dBFS: quiet on purpose, the volume setting only
turns them down. Deterministic (no randomness), so re-running gives identical files.
"""
import math
import os
import struct
import sys
import wave

RATE = 22050
PEAK = 0.2          # of full scale, before the user's volume


def note(freq, ms, gain=1.0, decay=7.0):
    """One ping: sine + quiet octave, 4 ms fade-in, exp decay (decay = e-folds over the note)."""
    n = int(RATE * ms / 1000)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * i / n) * min(1.0, i / (RATE * 0.004))
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)
        out.append(s * env * gain)
    return out


def sweep(f0, f1, ms, gain=1.0):
    """A short glide from f0 to f1 (phase-continuous), soft in and out."""
    n = int(RATE * ms / 1000)
    out, ph = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        ph += 2 * math.pi * f / RATE
        env = math.sin(math.pi * i / n) ** 1.5
        out.append(math.sin(ph) * env * gain)
    return out


def mix(parts):
    """parts: [(start_ms, samples)] -> one list."""
    end = max(int(RATE * s / 1000) + len(x) for s, x in parts)
    buf = [0.0] * end
    for s, x in parts:
        o = int(RATE * s / 1000)
        for i, v in enumerate(x):
            buf[o + i] += v
    return buf


SOUNDS = {
    "flyout":   lambda: mix([(0, note(880, 90, 0.8, 6)), (45, note(1320, 110, 0.7, 7))]),
    "launcher": lambda: mix([(0, sweep(520, 980, 120, 0.7)), (70, note(1175, 90, 0.5, 7))]),
    "notify":   lambda: mix([(0, note(1568, 90, 0.8, 6)), (95, note(2093, 150, 0.6, 7))]),
    "lock":     lambda: mix([(0, note(784, 80, 0.8, 6)), (70, note(523, 160, 0.8, 6))]),
    "unlock":   lambda: mix([(0, note(523, 80, 0.7, 6)), (70, note(784, 80, 0.7, 6)), (140, note(1175, 150, 0.6, 7))]),
}


def write(path, samples):
    top = max(1e-9, max(abs(v) for v in samples))
    scale = PEAK * 32767 / top
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * scale)) for v in samples))


def main(argv):
    out = argv[0] if argv else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    for name, fn in SOUNDS.items():
        write(os.path.join(out, name + ".wav"), fn())
        print(name + ".wav")


if __name__ == "__main__":
    main(sys.argv[1:])
