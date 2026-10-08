#!/usr/bin/env python3
"""Procedural audio generator for Big Battle Chess.

Every sound effect and music track shipped with the game is synthesised here
from scratch (oscillators, noise, Karplus-Strong strings, formant filters,
synthetic reverb), so all audio is original and covered by the project
license. Re-run to regenerate:

    python3 tools/generate_audio.py            # writes assets/audio/**
    python3 tools/generate_audio.py --only sfx

Requires numpy + scipy; ffmpeg (libvorbis) is used to encode music as OGG.
"""
import argparse
import os
import shutil
import subprocess
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
RNG = np.random.default_rng(20261008)


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def noise(dur):
    return RNG.uniform(-1.0, 1.0, int(dur * SR))


def env_exp(dur, decay, attack=0.002):
    t = t_axis(dur)
    e = np.exp(-t / max(decay, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def adsr(dur, a, d, s, r):
    n = int(dur * SR)
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na, endpoint=False)
    end_d = min(n, na + nd)
    e[na:end_d] = np.linspace(1, s, end_d - na, endpoint=False)
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def filt(x, kind, freq, order=2):
    nyq = SR * 0.5
    if kind == "band":
        lo, hi = freq
        sos = signal.butter(order, [max(lo, 10) / nyq, min(hi, nyq * 0.98) / nyq], btype="band", output="sos")
    else:
        sos = signal.butter(order, min(freq, nyq * 0.98) / nyq, btype=kind, output="sos")
    return signal.sosfilt(sos, x)


def saw(freq, dur, detune=0.0):
    t = t_axis(dur)
    return signal.sawtooth(2 * np.pi * freq * (1 + detune) * t + RNG.uniform(0, 6.28))


def sine_sweep(f0, f1, dur, curve="exp"):
    t = t_axis(dur)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pluck(freq, dur, brightness=0.5, decay=0.996):
    """Karplus-Strong plucked string implemented as an IIR comb (fast)."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    excite = np.zeros(n)
    burst = filt(RNG.uniform(-1, 1, period), "low", 1500 + 6000 * brightness)
    excite[:period] = burst
    a = np.zeros(period + 2)
    a[0] = 1.0
    a[period] = -0.5 * decay
    a[period + 1] = -0.5 * decay
    return signal.lfilter([1.0], a, excite)


def reverb(x, seconds=2.2, wet=0.3, seed=0, damp=4500):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / (SR * seconds / 6.0))
    ir = filt(ir, "low", damp)
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    tail = signal.fftconvolve(x, ir)[: len(x) + n]
    out = np.zeros(len(tail))
    out[: len(x)] += x * (1 - wet)
    out += tail * wet
    return out


def formant(x, vowel="a"):
    table = {
        "a": [(800, 1.0), (1150, 0.5), (2900, 0.25)],
        "o": [(450, 1.0), (800, 0.4), (2830, 0.15)],
        "e": [(400, 1.0), (1600, 0.5), (2700, 0.3)],
        "u": [(325, 1.0), (700, 0.3), (2530, 0.1)],
    }
    out = np.zeros(len(x))
    for f, g in table[vowel]:
        out += filt(x, "band", (f * 0.85, f * 1.15), 2) * g
    return out


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade(x, fin=0.002, fout=0.02):
    n_in, n_out = int(fin * SR), int(fout * SR)
    y = x.copy()
    if n_in:
        y[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        y[-n_out:] *= np.linspace(1, 0, n_out)
    return y


def mix(length, *parts):
    """parts: (signal, start_seconds, gain)."""
    out = np.zeros(int(length * SR))
    for sig, start, gain in parts:
        s = int(start * SR)
        if s >= len(out):
            continue
        e = min(len(out), s + len(sig))
        out[s:e] += sig[: e - s] * gain
    return out


def write_wav(path, x, stereo=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if stereo is not None:
        data = np.stack([x, stereo], axis=1)
        channels = 2
    else:
        data = x
        channels = 1
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

def metal_ring(base, dur, decay, partials=(1.0, 2.76, 5.40, 8.93, 13.34)):
    t = t_axis(dur)
    out = np.zeros(len(t))
    for i, r in enumerate(partials):
        f = base * r * RNG.uniform(0.98, 1.02)
        out += np.sin(2 * np.pi * f * t) * np.exp(-t / (decay / (1 + i * 0.6))) / (1 + i * 0.7)
    return out


def sfx_clash(v):
    base = [1150, 980, 1320][v % 3]
    ring = metal_ring(base, 1.3, 0.35)
    hit = filt(noise(0.05), "high", 2500) * env_exp(0.05, 0.008)
    low = np.sin(2 * np.pi * 180 * t_axis(0.2)) * env_exp(0.2, 0.04)
    x = mix(1.3, (ring, 0, 0.6), (hit, 0, 0.9), (low, 0, 0.4))
    return reverb(x, 1.4, 0.22, seed=v)


def sfx_clash_shield(v):
    thud = filt(noise(0.3), "low", 400) * env_exp(0.3, 0.06)
    tone = np.sin(2 * np.pi * (110 + 10 * v) * t_axis(0.4)) * env_exp(0.4, 0.09)
    ring = metal_ring(620 + 40 * v, 0.9, 0.18)
    x = mix(0.9, (thud, 0, 1.0), (tone, 0, 0.8), (ring, 0, 0.35))
    return reverb(x, 1.2, 0.2, seed=10 + v)


def sfx_whoosh(v):
    dur = 0.32 + 0.06 * v
    n = noise(dur)
    t = t_axis(dur)
    # Swept band-pass approximated by crossfading three static bands.
    lo = filt(n, "band", (300, 900))
    mid = filt(n, "band", (900, 2500))
    hi = filt(n, "band", (2500, 6000))
    k = t / dur
    x = lo * (1 - k) + mid * np.sin(np.pi * k) + hi * k * 0.6
    return fade(x * np.sin(np.pi * k) ** 1.5, 0.005, 0.03)


def sfx_impact_flesh(v):
    thump = sine_sweep(140, 45, 0.35) * env_exp(0.35, 0.08)
    crunch = filt(noise(0.12), "band", (400, 2500)) * env_exp(0.12, 0.03)
    return mix(0.4, (thump, 0, 1.0), (crunch, 0, 0.6))


def sfx_slam(v):
    boom = sine_sweep(90, 28, 1.6) * env_exp(1.6, 0.35)
    rumble = filt(noise(2.0), "low", 180) * env_exp(2.0, 0.6)
    crack = filt(noise(0.15), "high", 1500) * env_exp(0.15, 0.03)
    debris = np.zeros(int(2.0 * SR))
    for _ in range(14):
        s = RNG.uniform(0.1, 1.2)
        d = filt(noise(0.05), "band", (1500, 5000)) * env_exp(0.05, 0.01)
        debris = debris + mix(2.0, (d, s, RNG.uniform(0.1, 0.3)))
    x = mix(2.0, (boom, 0, 1.0), (rumble, 0, 0.8), (crack, 0, 0.7), (debris, 0, 1.0))
    return reverb(x, 2.5, 0.3, seed=20 + v)


def sfx_step(v):
    thud = filt(noise(0.12), "low", 600) * env_exp(0.12, 0.025)
    jingle = metal_ring(2400 + 300 * v, 0.15, 0.03) * 0.25
    return mix(0.15, (thud, 0, 1.0), (jingle, 0.01, 1.0))


def sfx_hoof(v):
    clop = filt(noise(0.08), "band", (500, 1600)) * env_exp(0.08, 0.012)
    body = np.sin(2 * np.pi * (240 + 30 * v) * t_axis(0.1)) * env_exp(0.1, 0.02)
    return mix(0.12, (clop, 0, 1.0), (body, 0, 0.5))


def sfx_land(v):
    return sfx_impact_flesh(v) * 0.8 + mix(0.4, (filt(noise(0.4), "low", 300) * env_exp(0.4, 0.1), 0, 0.6))


def sfx_armor_fall(v):
    x = np.zeros(int(1.4 * SR))
    for i in range(6):
        s = i * RNG.uniform(0.06, 0.14)
        x = x + mix(1.4, (metal_ring(RNG.uniform(500, 1600), 0.5, 0.08), s, 0.4 / (1 + i * 0.3)))
    thud = filt(noise(0.4), "low", 350) * env_exp(0.4, 0.1)
    return reverb(mix(1.4, (x, 0, 1.0), (thud, 0, 0.9)), 1.4, 0.2, seed=30 + v)


def sfx_magic_charge(v):
    dur = 1.0
    t = t_axis(dur)
    f = 300 * (4.0 ** (t / dur))
    mod = np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR) * 3.0
    car = np.sin(2 * np.pi * np.cumsum(f) / SR + mod)
    shimmer = filt(noise(dur), "high", 5000) * 0.15
    x = (car * 0.6 + shimmer) * np.linspace(0.1, 1.0, len(t)) ** 1.5
    return reverb(fade(x, 0.01, 0.05), 1.5, 0.35, seed=40 + v)


def sfx_magic_cast(v):
    whoosh = sfx_whoosh(v)
    chime = metal_ring(1800, 1.0, 0.25, (1.0, 2.0, 3.0, 4.2)) * 0.4
    return reverb(mix(1.0, (whoosh, 0, 0.8), (chime, 0.02, 1.0)), 1.6, 0.35, seed=50 + v)


def sfx_magic_impact(v):
    burst = filt(noise(0.5), "band", (300, 4000)) * env_exp(0.5, 0.1)
    boom = sine_sweep(220, 60, 0.6) * env_exp(0.6, 0.15)
    sparkle = metal_ring(2600, 1.0, 0.2, (1.0, 1.5, 2.25, 3.4)) * 0.3
    return reverb(mix(1.2, (burst, 0, 0.8), (boom, 0, 0.9), (sparkle, 0.03, 1.0)), 1.8, 0.35, seed=60 + v)


def sfx_thunder(v):
    crack = filt(noise(0.2), "high", 1200) * env_exp(0.2, 0.04)
    rumble = filt(noise(2.5), "low", 220) * env_exp(2.5, 0.8)
    x = mix(2.5, (crack, 0, 1.0), (rumble, 0.02, 1.2))
    return reverb(x, 2.5, 0.35, seed=70 + v)


def sfx_dash(v):
    swish = sfx_whoosh(2) * 0.8
    zing = sine_sweep(3000, 1200, 0.3) * env_exp(0.3, 0.08) * 0.3
    return mix(0.45, (swish, 0, 1.0), (zing, 0, 1.0))


def sfx_power_up(v):
    dur = 2.4
    t = t_axis(dur)
    rumble = filt(noise(dur), "low", 160) * np.linspace(0.2, 1.0, len(t))
    chord = np.zeros(len(t))
    for m in (50, 57, 62, 65, 69):
        chord += formant(saw(midi(m), dur, 0.002) + saw(midi(m), dur, -0.003), "a")
    chord *= np.linspace(0, 1, len(t)) ** 2
    rise = sine_sweep(80, 320, dur) * np.linspace(0, 0.4, len(t))
    return reverb(fade(rumble * 0.6 + chord * 0.25 + rise, 0.05, 0.2), 2.0, 0.3, seed=80 + v)


def sfx_finisher_impact(v):
    boom = sine_sweep(110, 25, 2.5) * env_exp(2.5, 0.6)
    crack = filt(noise(0.3), "high", 900) * env_exp(0.3, 0.05)
    ring = metal_ring(700, 2.0, 0.5) * 0.4
    rumble = filt(noise(3.0), "low", 150) * env_exp(3.0, 1.0)
    x = mix(3.0, (boom, 0, 1.0), (crack, 0, 0.9), (ring, 0, 1.0), (rumble, 0, 0.8))
    return reverb(x, 3.0, 0.4, seed=90 + v)


def sfx_slash_hit(v):
    return mix(0.6, (sfx_whoosh(v), 0, 0.7), (sfx_impact_flesh(v), 0.12, 1.0), (metal_ring(3000, 0.3, 0.05), 0.12, 0.2))


def sfx_blade_grind(v):
    dur = 1.4
    n = filt(noise(dur), "band", (1800, 6000))
    t = t_axis(dur)
    am = 0.6 + 0.4 * np.sin(2 * np.pi * 23 * t + np.sin(2 * np.pi * 3 * t) * 4)
    ring = metal_ring(1450, dur, 0.6) * 0.2
    return fade((n * am * 0.6 + ring) * np.sin(np.pi * t / dur) ** 0.5, 0.02, 0.1)


def sfx_heartbeat(v):
    beat = sine_sweep(70, 40, 0.18) * env_exp(0.18, 0.05)
    return mix(1.2, (beat, 0, 1.0), (beat, 0.28, 0.7), (beat, 0.95, 0.9))


def sfx_wind(v):
    dur = 3.5
    n = filt(noise(dur), "band", (200, 1400))
    t = t_axis(dur)
    swell = 0.4 + 0.6 * np.sin(np.pi * t / dur) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.7 * t))
    return fade(n * swell, 0.3, 0.6)


def sfx_draw_weapon(v):
    dur = 0.7
    n = filt(noise(dur), "band", (2500, 9000)) * env_exp(dur, 0.25)
    ring = metal_ring(2100, dur, 0.3) * 0.3
    return reverb(fade(n * 0.6 + ring, 0.01, 0.05), 1.0, 0.25, seed=100 + v)


def sfx_jump(v):
    return sfx_whoosh(0)[: int(0.25 * SR)] * np.linspace(1, 0.3, int(0.25 * SR))


def voice(vowel, f0_start, f0_end, dur, rough=0.3):
    t = t_axis(dur)
    f0 = f0_start * (f0_end / f0_start) ** (t / dur)
    f0 *= 1 + 0.02 * np.sin(2 * np.pi * 5.5 * t)
    phase = np.cumsum(f0) / SR
    pulse = signal.sawtooth(2 * np.pi * phase) + rough * RNG.uniform(-1, 1, len(t))
    v = formant(pulse, vowel)
    return normalize(v * adsr(dur, 0.03, 0.1, 0.8, 0.12), 0.8)


def sfx_grunt(v):
    return voice(["a", "u", "e"][v % 3], 160, 110, 0.28, 0.5)


def sfx_battle_cry(v):
    return reverb(voice("a", 170, 210, 0.9, 0.45), 1.5, 0.3, seed=110 + v)


def sfx_death_cry(v):
    return reverb(voice("o", 200, 90, 1.1, 0.5), 1.8, 0.35, seed=120 + v)


def sfx_victory_cry(v):
    return reverb(voice("a", 180, 240, 1.0, 0.35), 1.8, 0.35, seed=130 + v)


def sfx_horse_neigh(v):
    dur = 1.0
    t = t_axis(dur)
    f = 900 * (0.45 ** (t / dur)) * (1 + 0.08 * np.sin(2 * np.pi * 14 * t))
    x = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR)
    x = formant(x, "e") * adsr(dur, 0.04, 0.2, 0.7, 0.3)
    return reverb(normalize(x, 0.7), 1.2, 0.25, seed=140 + v)


def sfx_ui(kind):
    if kind == "hover":
        return np.sin(2 * np.pi * 1800 * t_axis(0.05)) * env_exp(0.05, 0.012) * 0.4
    if kind == "click":
        wood = filt(noise(0.06), "band", (800, 2500)) * env_exp(0.06, 0.01)
        chime = metal_ring(1500, 0.4, 0.08, (1.0, 2.0, 3.0)) * 0.35
        return mix(0.4, (wood, 0, 0.8), (chime, 0.005, 1.0))
    if kind == "back":
        return mix(0.3, (metal_ring(900, 0.3, 0.06, (1.0, 2.0)), 0, 0.4), (filt(noise(0.05), "low", 1500) * env_exp(0.05, 0.01), 0, 0.6))
    if kind == "open":
        n = filt(noise(0.4), "band", (1500, 7000)) * np.sin(np.pi * t_axis(0.4) / 0.4) ** 2
        return fade(n * 0.5, 0.01, 0.05)
    if kind == "error":
        return np.sin(2 * np.pi * 180 * t_axis(0.25)) * env_exp(0.25, 0.08) * 0.6
    raise ValueError(kind)


def sfx_piece_place(v):
    thunk = filt(noise(0.15), "low", 900) * env_exp(0.15, 0.03)
    tone = np.sin(2 * np.pi * (330 + 40 * v) * t_axis(0.2)) * env_exp(0.2, 0.05) * 0.4
    return reverb(mix(0.25, (thunk, 0, 1.0), (tone, 0, 1.0)), 0.8, 0.2, seed=150 + v)


def sfx_check(v):
    bell = metal_ring(520, 2.5, 0.8, (1.0, 2.0, 2.4, 3.0, 4.2, 5.4))
    return reverb(bell * 0.6, 2.5, 0.35, seed=160)


def sfx_checkmate(v):
    gong = metal_ring(110, 5.0, 2.0, (1.0, 1.48, 2.0, 2.53, 3.2, 4.1))
    boom = sine_sweep(80, 40, 2.0) * env_exp(2.0, 0.6)
    return reverb(mix(5.0, (gong, 0, 0.6), (boom, 0, 0.7)), 3.5, 0.4, seed=170)


def sfx_promotion(v):
    dur = 2.2
    chord = np.zeros(int(dur * SR))
    for i, m in enumerate((62, 66, 69, 74, 78)):
        tone = formant(saw(midi(m), dur, 0.002), "a") * adsr(dur, 0.2 + i * 0.08, 0.3, 0.7, 0.8)
        chord += tone
    sparkle = filt(noise(dur), "high", 6000) * np.linspace(0, 0.2, int(dur * SR))
    return reverb(normalize(chord * 0.3 + sparkle, 0.7), 2.5, 0.4, seed=180)


def sfx_game_start(v):
    dur = 2.0
    horn = np.zeros(int(dur * SR))
    for m, s in ((50, 0.0), (57, 0.35), (62, 0.7)):
        d = dur - s
        tone = (saw(midi(m), d) * 0.6 + saw(midi(m), d, 0.004) * 0.4)
        tone = filt(tone, "low", 1800) * adsr(d, 0.08, 0.2, 0.7, 0.5)
        horn = horn + mix(dur, (tone, s, 0.4))
    return reverb(horn, 2.5, 0.35, seed=190)


def sfx_capture_quick(v):
    return mix(0.7, (sfx_whoosh(v), 0, 0.6), (sfx_clash(v), 0.1, 0.8))


SFX = {
    "clash": (sfx_clash, 3), "clash_shield": (sfx_clash_shield, 2), "whoosh": (sfx_whoosh, 3),
    "impact_flesh": (sfx_impact_flesh, 2), "slam": (sfx_slam, 2), "step": (sfx_step, 3),
    "hoof": (sfx_hoof, 2), "land": (sfx_land, 1), "armor_fall": (sfx_armor_fall, 2),
    "magic_charge": (sfx_magic_charge, 1), "magic_cast": (sfx_magic_cast, 2), "magic_impact": (sfx_magic_impact, 2),
    "thunder": (sfx_thunder, 2), "dash": (sfx_dash, 1), "power_up": (sfx_power_up, 1),
    "finisher_impact": (sfx_finisher_impact, 1), "slash_hit": (sfx_slash_hit, 2), "blade_grind": (sfx_blade_grind, 1),
    "heartbeat": (sfx_heartbeat, 1), "wind": (sfx_wind, 1), "draw_weapon": (sfx_draw_weapon, 1),
    "jump": (sfx_jump, 1), "grunt": (sfx_grunt, 3), "battle_cry": (sfx_battle_cry, 2), "death_cry": (sfx_death_cry, 2),
    "victory_cry": (sfx_victory_cry, 1), "horse_neigh": (sfx_horse_neigh, 1), "piece_place": (sfx_piece_place, 2),
    "check": (sfx_check, 1), "checkmate": (sfx_checkmate, 1), "promotion": (sfx_promotion, 1),
    "game_start": (sfx_game_start, 1), "capture_quick": (sfx_capture_quick, 2),
}


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

def chord_notes(root, quality):
    third = 3 if quality == "m" else 4
    return [root, root + third, root + 7]


def strings_pad(notes, dur, bright=1200):
    out = np.zeros(int(dur * SR))
    for m in notes:
        for det in (-0.004, 0.0, 0.004):
            out += saw(midi(m), dur, det)
    out = filt(out, "low", bright)
    return out * adsr(dur, min(0.6, dur * 0.3), 0.3, 0.85, min(0.8, dur * 0.3)) / (len(notes) * 3)


def choir(notes, dur, vowel="a"):
    out = np.zeros(int(dur * SR))
    for m in notes:
        for det in (-0.006, 0.0, 0.005):
            out += formant(saw(midi(m), dur, det), vowel)
    t = t_axis(dur)
    out *= 1 + 0.05 * np.sin(2 * np.pi * 4.8 * t)
    return out * adsr(dur, min(0.5, dur * 0.3), 0.2, 0.9, min(0.6, dur * 0.3)) / (len(notes) * 3)


def brass(notes, dur):
    out = np.zeros(int(dur * SR))
    for m in notes:
        tone = saw(midi(m), dur) + saw(midi(m), dur, 0.003)
        dark = filt(tone, "low", 700)
        bright = filt(tone, "low", 3000)
        e = adsr(dur, 0.05, 0.25, 0.6, 0.15)
        out += dark * (1 - e * 0.6) * e + bright * e * 0.6
    return out / len(notes)


def flute(m, dur):
    t = t_axis(dur)
    f = midi(m) * (1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.3, 0, 1))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.25 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    breath = filt(noise(dur), "band", (midi(m), midi(m) * 3)) * 0.06
    return (tone + breath) * adsr(dur, 0.06, 0.1, 0.8, min(0.25, dur * 0.4))


def taiko(gain=1.0):
    body = sine_sweep(115, 48, 0.9) * env_exp(0.9, 0.22)
    skin = filt(noise(0.08), "low", 1200) * env_exp(0.08, 0.015)
    return mix(0.9, (body, 0, 1.0), (skin, 0, 0.5)) * gain


def frame_drum():
    return mix(0.2, (filt(noise(0.2), "band", (180, 2500)) * env_exp(0.2, 0.04), 0, 1.0), (np.sin(2 * np.pi * 190 * t_axis(0.2)) * env_exp(0.2, 0.05), 0, 0.5))


def timpani(m):
    t = t_axis(1.6)
    tone = np.sin(2 * np.pi * midi(m) * t) * env_exp(1.6, 0.5) + 0.4 * np.sin(2 * np.pi * midi(m) * 1.5 * t) * env_exp(1.6, 0.3)
    return mix(1.6, (tone, 0, 1.0), (filt(noise(0.05), "low", 800) * env_exp(0.05, 0.01), 0, 1.0))


def place(buf, sig, start, gain=1.0):
    s = int(start * SR)
    if s >= len(buf):
        return
    e = min(len(buf), s + len(sig))
    buf[s:e] += sig[: e - s] * gain


def stereo_master(left, right, seed, wet=0.3, seconds=2.6):
    l = reverb(left, seconds, wet, seed=seed)
    r = reverb(right, seconds, wet, seed=seed + 1)
    n = len(left)
    # Fold the reverb tail back into the start so the loop is seamless.
    l_out = l[:n].copy()
    r_out = r[:n].copy()
    tail = len(l) - n
    l_out[:tail] += l[n:]
    r_out[:tail] += r[n:]
    peak = max(np.max(np.abs(l_out)), np.max(np.abs(r_out))) + 1e-9
    return l_out / peak * 0.85, r_out / peak * 0.85


def music_menu():
    bpm, bars = 72, 16
    beat = 60.0 / bpm
    bar = beat * 4
    dur = bar * bars
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    prog = [(50, "m"), (46, ""), (48, ""), (45, "m"), (50, "m"), (43, "m"), (46, ""), (45, "")]
    for i, (root, q) in enumerate(prog):
        start = i * 2 * bar
        notes = chord_notes(root, q)
        pad = strings_pad([n + 12 for n in notes] + [root], 2 * bar)
        place(left, pad, start, 0.5)
        place(right, pad, start, 0.5)
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
        for k in range(16):
            m = arp[k % 4] if (k // 4) % 2 == 0 else arp[3 - k % 4]
            p = pluck(midi(m), 1.6, 0.5)
            pan = 0.3 + 0.4 * ((k % 4) / 3)
            place(left, p, start + k * beat * 0.5, 0.22 * (1 - pan))
            place(right, p, start + k * beat * 0.5, 0.22 * pan)
        if i >= 4:
            tim = timpani(root - 12)
            place(left, tim, start, 0.25)
            place(right, tim, start, 0.25)
    melody = [(74, 2), (77, 1), (76, 1), (74, 2), (72, 1), (69, 1), (70, 2), (72, 1), (74, 1), (76, 4),
              (77, 1), (76, 1), (74, 1), (72, 1), (74, 2), (69, 2), (70, 1), (72, 1), (74, 1), (76, 1), (73, 4)]
    t0 = 4 * bar
    for m, beats in melody:
        f = flute(m, beats * beat * 0.95)
        place(left, f, t0, 0.22)
        place(right, f, t0, 0.18)
        t0 += beats * beat
    for k in range(0, len(melody)):
        pass
    t0 = 12 * bar
    for m, beats in melody[:10]:
        f = flute(m - 12, beats * beat * 0.95)
        place(left, f, t0, 0.12)
        place(right, f, t0, 0.15)
        t0 += beats * beat
    return stereo_master(left, right, 300)


def music_board():
    bpm, bars = 60, 16
    beat = 60.0 / bpm
    bar = beat * 4
    dur = bar * bars
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    prog = [(50, "m"), (48, ""), (46, ""), (48, ""), (50, "m"), (53, ""), (48, ""), (45, "")]
    for i, (root, q) in enumerate(prog):
        start = i * 2 * bar
        notes = chord_notes(root, q)
        pad = strings_pad([n + 12 for n in notes], 2 * bar, 900)
        place(left, pad, start, 0.35)
        place(right, pad, start, 0.35)
        pattern = [0, 2, 1, 2, 0, 2, 1, 3]
        tones = [notes[0], notes[1] + 12, notes[2], notes[0] + 24]
        for k in range(16):
            p = pluck(midi(tones[pattern[k % 8]] + 12), 2.0, 0.35, 0.997)
            pan = 0.35 + 0.3 * np.sin(k)
            place(left, p, start + k * beat * 0.5 + RNG.uniform(0, 0.015), 0.2 * (1 - pan))
            place(right, p, start + k * beat * 0.5 + RNG.uniform(0, 0.015), 0.2 * pan)
        if i % 2 == 1:
            bell = metal_ring(midi(notes[2] + 24), 3.0, 1.0, (1.0, 2.0, 3.01, 4.17)) * 0.08
            place(left, bell, start + bar, 0.8)
            place(right, bell, start + bar + 0.02, 1.0)
    return stereo_master(left, right, 400, 0.35, 3.0)


def music_battle():
    bpm, bars = 128, 16
    beat = 60.0 / bpm
    bar = beat * 4
    dur = bar * bars
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    prog = [(50, "m"), (46, ""), (48, ""), (45, "")]
    ostinato = [0, 0, 12, 0, 10, 0, 7, 0]
    big = taiko(1.0)
    small = frame_drum()
    for b in range(bars):
        start = b * bar
        root, q = prog[(b // 2) % 4]
        notes = chord_notes(root, q)
        for k, off in enumerate(ostinato):
            m = root - 12 + off
            tone = filt(saw(midi(m), beat * 0.5 * 0.9) + saw(midi(m), beat * 0.45, 0.005), "low", 900) * adsr(beat * 0.45, 0.005, 0.1, 0.6, 0.05)
            place(left, tone, start + k * beat * 0.5, 0.18)
            place(right, tone, start + k * beat * 0.5, 0.18)
        for pos in (0, 1.5, 2, 3):
            place(left, big, start + pos * beat, 0.5)
            place(right, big, start + pos * beat, 0.5)
        for pos in (0.5, 1, 2.5, 3.5, 3.75):
            place(left, small, start + pos * beat, 0.18)
            place(right, small, start + pos * beat, 0.22)
        if b % 2 == 0:
            st = brass([n + 12 for n in notes], beat * 1.5)
            place(left, st, start, 0.32)
            place(right, st, start, 0.32)
            st2 = brass([n + 12 for n in notes], beat * 0.9)
            place(left, st2, start + beat * 2.5, 0.25)
            place(right, st2, start + beat * 2.5, 0.25)
        if b >= 8:
            ch = choir([n + 12 for n in notes], bar)
            place(left, ch, start, 0.3)
            place(right, ch, start, 0.3)
    return stereo_master(left, right, 500, 0.22, 2.0)


def music_climax():
    bpm, bars = 140, 8
    beat = 60.0 / bpm
    bar = beat * 4
    dur = bar * bars
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    prog = [(50, "m"), (46, ""), (43, "m"), (45, "")]
    big = taiko(1.0)
    small = frame_drum()
    for b in range(bars):
        start = b * bar
        root, q = prog[(b // 2) % 4]
        notes = chord_notes(root, q)
        ch = choir([n + 12 for n in notes] + [root + 24], bar, "a" if b % 2 == 0 else "o")
        place(left, ch, start, 0.45)
        place(right, ch, start, 0.45)
        pad = strings_pad([n + 24 for n in notes], bar, 2500)
        place(left, pad, start, 0.3)
        place(right, pad, start, 0.3)
        for k in range(8):
            place(left, big if k % 2 == 0 else small, start + k * beat * 0.5, 0.45 if k % 2 == 0 else 0.25)
            place(right, big if k % 2 == 0 else small, start + k * beat * 0.5, 0.45 if k % 2 == 0 else 0.25)
        for k in range(16):
            place(left, small, start + k * beat * 0.25, 0.08)
        st = brass([n + 12 for n in notes], beat * 0.7)
        for pos in (0, 1.5, 3):
            place(left, st, start + pos * beat, 0.25)
            place(right, st, start + pos * beat, 0.25)
    return stereo_master(left, right, 600, 0.25, 2.0)


def music_victory():
    beat = 60.0 / 100
    dur = 7.0
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    fanfare = [(62, 0, 0.5), (69, 0.5, 0.5), (74, 1.0, 0.75), (78, 1.75, 0.25), (81, 2.0, 2.5)]
    for m, s, d in fanfare:
        b = brass([m], d * beat * 2)
        place(left, b, s * beat, 0.45)
        place(right, b, s * beat, 0.45)
    ch = brass([62, 66, 69, 74], 4.0)
    place(left, ch, 2.0 * beat, 0.35)
    place(right, ch, 2.0 * beat, 0.35)
    for k in range(10):
        tim = timpani(38 if k % 2 == 0 else 45)
        place(left, tim, 2.0 * beat + k * 0.08, 0.12)
        place(right, tim, 2.0 * beat + k * 0.08, 0.12)
    place(left, timpani(38), 2.0 * beat + 0.9, 0.5)
    place(right, timpani(38), 2.0 * beat + 0.9, 0.5)
    l = reverb(left, 3.0, 0.35, seed=700)[: len(left)]
    r = reverb(right, 3.0, 0.35, seed=701)[: len(right)]
    l, r = fade(l, 0.01, 1.0), fade(r, 0.01, 1.0)
    p = max(np.max(np.abs(l)), np.max(np.abs(r)))
    return l / p * 0.85, r / p * 0.85


def music_defeat():
    dur = 8.0
    left = np.zeros(int(dur * SR))
    right = np.zeros(int(dur * SR))
    for i, (root, q) in enumerate([(50, "m"), (46, ""), (45, "")]):
        ch = choir(chord_notes(root, q) + [root - 12], 3.0, "o")
        place(left, ch, i * 2.5, 0.5)
        place(right, ch, i * 2.5, 0.5)
    gong = metal_ring(90, 6.0, 2.5, (1.0, 1.48, 2.0, 2.53, 3.2))
    place(left, gong, 0.0, 0.3)
    place(right, gong, 0.02, 0.3)
    l = reverb(left, 3.5, 0.4, seed=800)[: len(left)]
    r = reverb(right, 3.5, 0.4, seed=801)[: len(right)]
    l, r = fade(l, 0.01, 1.5), fade(r, 0.01, 1.5)
    p = max(np.max(np.abs(l)), np.max(np.abs(r)))
    return l / p * 0.8, r / p * 0.8


def ambience_hall():
    dur = 24.0
    wind = filt(noise(dur), "band", (120, 700))
    t = t_axis(dur)
    wind *= 0.5 + 0.3 * np.sin(2 * np.pi * t / dur) + 0.2 * np.sin(2 * np.pi * 3 * t / dur)
    crackle = np.zeros(len(t))
    for _ in range(260):
        s = RNG.uniform(0, dur - 0.05)
        c = filt(noise(0.02), "band", (1500, 6000)) * env_exp(0.02, 0.004)
        place(crackle, c, s, RNG.uniform(0.05, 0.3))
    fire = filt(noise(dur), "low", 300) * 0.3
    x = wind * 0.4 + crackle + fire
    # Seamless loop: crossfade end into start.
    n = int(2.0 * SR)
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    x = x[:-n]
    return normalize(x, 0.6)


MUSIC = {
    "menu": music_menu, "board": music_board, "battle": music_battle,
    "climax": music_climax, "victory": music_victory, "defeat": music_defeat,
}


def encode_ogg(wav_path, ogg_path, quality=4):
    if shutil.which("ffmpeg") is None:
        return False
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), ogg_path]
    if subprocess.run(cmd).returncode != 0:
        return False
    os.remove(wav_path)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["sfx", "music", "ambience"], default=None)
    args = ap.parse_args()
    if args.only in (None, "sfx"):
        for name, (fn, variants) in SFX.items():
            for v in range(variants):
                x = fade(normalize(fn(v), 0.9), 0.001, 0.01)
                wav = os.path.join(ROOT, "sfx", f"{name}_{v}.wav")
                write_wav(wav, x)
                encode_ogg(wav, wav[:-4] + ".ogg", 5)
        for kind in ("hover", "click", "back", "open", "error"):
            wav = os.path.join(ROOT, "sfx", f"ui_{kind}_0.wav")
            write_wav(wav, fade(normalize(sfx_ui(kind), 0.7), 0.001, 0.005))
            encode_ogg(wav, wav[:-4] + ".ogg", 5)
        print(f"sfx: {sum(v for _, v in SFX.values()) + 5} files")
    if args.only in (None, "music"):
        for name, fn in MUSIC.items():
            l, r = fn()
            wav = os.path.join(ROOT, "music", f"{name}.wav")
            write_wav(wav, l, r)
            encode_ogg(wav, wav[:-4] + ".ogg")
            print("music:", name, f"{len(l) / SR:.1f}s")
    if args.only in (None, "ambience"):
        wav = os.path.join(ROOT, "ambience", "hall.wav")
        write_wav(wav, ambience_hall())
        encode_ogg(wav, wav[:-4] + ".ogg", 3)
        print("ambience: hall")


if __name__ == "__main__":
    main()
