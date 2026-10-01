#!/usr/bin/env python3
"""Synthesizes the theme sound effects that replace Panel Attack's Unity Asset
Store sounds (which may only be shipped with official Panel Attack releases).

Everything here is generated from scratch by this script, so the output is
dedicated to the public domain (CC0 1.0), like the script itself.

usage: tools/make_sfx.py OUTDIR      (needs numpy and ffmpeg)
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 22050


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, attack=0.004, release=None, curve=4.0):
    """attack ramp, then exponential-ish decay to zero"""
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    rest = n - a
    if rest > 0:
        e[a:] = np.exp(-curve * np.linspace(0, 1, rest))
        e[a:] *= np.linspace(1, 0, rest) ** 0.3  # land exactly on zero
    return e


def osc(freq, dur, shape="square", duty=0.5, vib=0.0, vibrate=6.0):
    tt = t(dur)
    f = np.broadcast_to(freq, tt.shape) if np.ndim(freq) else np.full(tt.shape, float(freq))
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * vibrate * tt))
    phase = np.cumsum(f) / SR
    frac = phase % 1.0
    if shape == "square":
        return np.where(frac < duty, 1.0, -1.0)
    if shape == "triangle":
        return 4 * np.abs(frac - 0.5) - 1
    if shape == "saw":
        return 2 * frac - 1
    return np.sin(2 * np.pi * phase)


def soften(x, amount=0.35):
    """one-pole low-pass to take the edge off square waves"""
    y = np.empty_like(x)
    acc = 0.0
    k = 1 - amount
    for i, v in enumerate(x):
        acc = acc * amount + v * k
        y[i] = acc
    return y


def note(freq, dur, shape="square", vol=0.5, attack=0.004, curve=4.0, duty=0.5, soft=0.35, vib=0.0):
    x = osc(freq, dur, shape, duty, vib)
    if soft:
        x = soften(x, soft)
    return x * env(len(x), attack, curve=curve) * vol


def sweep(f0, f1, dur, shape="square", vol=0.5, curve=4.0, duty=0.5):
    tt = t(dur)
    f = f0 * (f1 / f0) ** (tt / dur)
    x = soften(osc(f, dur, shape, duty), 0.3)
    return x * env(len(x), 0.003, curve=curve) * vol


def noise(dur, vol=0.5, lp=0.8, curve=6.0, seed=1):
    rng = np.random.default_rng(seed)
    x = rng.uniform(-1, 1, int(SR * dur))
    x = soften(x, lp)
    return x * env(len(x), 0.002, curve=curve) * vol


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(SR * gap)))
    return np.concatenate(out)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def thud(base, dur, vol):
    tt = t(dur)
    f = base * (1 + 1.5 * np.exp(-tt * 30))  # quick downward pitch drop
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(tt), 0.002, curve=7) * vol
    return mix(body, noise(dur * 0.4, vol * 0.35, lp=0.92, curve=9))


C5, E5, G5, A5, B5 = 523.25, 659.25, 783.99, 880.0, 987.77
C6, D6, E6, G6 = 1046.5, 1174.66, 1318.51, 1567.98

SOUNDS = {
    # menus
    "menu_move": lambda: note(A5, 0.05, "square", 0.30, duty=0.25, curve=6),
    "menu_validate": lambda: seq(note(E5, 0.05, vol=0.32, duty=0.25), note(B5, 0.10, vol=0.32, duty=0.25, curve=5)),
    "menu_cancel": lambda: seq(note(B5, 0.05, vol=0.30, duty=0.25), note(E5, 0.10, vol=0.30, duty=0.25, curve=5)),
    "notification": lambda: seq(note(G5, 0.09, "triangle", 0.45, soft=0), note(D6, 0.22, "triangle", 0.45, soft=0, curve=3)),
    # in game
    "move": lambda: note(C6, 0.025, "square", 0.16, duty=0.125, curve=8),
    "swap": lambda: mix(sweep(1400, 700, 0.06, "square", 0.22, curve=5, duty=0.25), noise(0.03, 0.12, lp=0.5)),
    "land": lambda: thud(110, 0.09, 0.45),
    "thud_1": lambda: thud(90, 0.16, 0.55),
    "thud_2": lambda: thud(70, 0.24, 0.65),
    "thud_3": lambda: thud(55, 0.34, 0.75),
    "countdown": lambda: note(A5, 0.14, "square", 0.32, duty=0.5, curve=3),
    "go": lambda: note(A5 * 2, 0.40, "square", 0.32, duty=0.5, curve=2.5, vib=0.004),
    "fanfare1": lambda: seq(*[note(f, 0.07, vol=0.30, duty=0.25, curve=3) for f in (C5, E5, G5)], note(C6, 0.25, vol=0.30, duty=0.25, curve=2.5)),
    "fanfare2": lambda: seq(*[note(f, 0.065, vol=0.30, duty=0.25, curve=3) for f in (C5, E5, G5, C6, E6)], note(G6, 0.30, vol=0.30, duty=0.25, curve=2.2, vib=0.005)),
    "fanfare3": lambda: seq(*[note(f, 0.06, vol=0.30, duty=0.25, curve=3) for f in (C5, E5, G5, C6, E5, G5, C6, E6)],
                            mix(note(C6, 0.5, vol=0.22, duty=0.25, curve=1.8, vib=0.006), note(G6, 0.5, vol=0.18, duty=0.5, curve=1.8))),
    "gameover": lambda: seq(*[note(f, 0.16, "triangle", 0.45, soft=0, curve=2.5) for f in (G5, 698.46, 622.25)],
                            note(523.25, 0.6, "triangle", 0.45, soft=0, curve=1.8, vib=0.008)),
    # fallback chain sound for characters without their own
    "chain": lambda: seq(note(E6, 0.05, vol=0.28, duty=0.25), note(G6, 0.16, vol=0.28, duty=0.25, curve=3)),
}


def write_ogg(name, samples, outdir):
    samples = np.clip(samples, -1, 1)
    pcm = (samples * 32767).astype("<i2").tobytes()
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    out = os.path.join(outdir, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    os.unlink(path)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "sfx"
    os.makedirs(outdir, exist_ok=True)
    for name, fn in SOUNDS.items():
        write_ogg(name, fn(), outdir)
    print("wrote %d sounds to %s" % (len(SOUNDS), outdir))


if __name__ == "__main__":
    main()
