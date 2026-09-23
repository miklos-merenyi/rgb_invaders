#!/usr/bin/env python3
"""Synthesises the game's sound effects into assets/sounds/*.wav.

Run from the repo root:  python3 tool/make_sounds.py   (needs numpy)

Fire sounds use the same note per colour combination as rigobert
(F minor pentatonic): R=F4, G=G4, B=Bb4, RG=C5, RB=D5, GB=F5, RGB=G5.
"""

import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")

# Colour mask (R=1, G=2, B=4) -> note frequency.
FIRE_NOTES = {
    1: 349.23,  # red      F4
    2: 392.00,  # green    G4
    4: 466.16,  # blue     Bb4
    3: 523.25,  # yellow   C5
    5: 587.33,  # magenta  D5
    6: 698.46,  # cyan     F5
    7: 783.99,  # white    G5
}


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def envelope(n, attack=0.004, release=0.02):
    """Linear attack and release ramps so clips never click."""
    env = np.ones(n)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    env[:a] = np.linspace(0, 1, a)
    env[-r:] *= np.linspace(1, 0, r)
    return env


def sweep_phase(freqs):
    """Phase for a time-varying frequency curve."""
    return 2 * np.pi * np.cumsum(freqs) / RATE


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be an array (per-sample, in Hz)."""
    cutoff = np.broadcast_to(cutoff, x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def save(name, x, peak):
    x = x / (np.max(np.abs(x)) or 1) * peak
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def fire(freq):
    """A bright upward 'zap' that settles on the colour's note."""
    t = t_axis(0.34)
    glide = freq * (0.5 + 0.5 * (1 - np.exp(-t / 0.025)))
    glide *= 1 + 0.004 * np.sin(2 * np.pi * 7 * t)  # light vibrato
    ph = sweep_phase(glide)
    tone = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    shimmer = 0.18 * np.sin(sweep_phase(glide * 2.01))
    x = (tone + shimmer) * np.exp(-t / 0.11)
    return x * envelope(len(t))


def explosion():
    """Noise burst with a falling filter and a low thump."""
    rng = np.random.default_rng(1)
    t = t_axis(0.55)
    noise = rng.uniform(-1, 1, len(t))
    crackle = lowpass(noise, 7000 * np.exp(-t / 0.09) + 250)
    crackle *= np.exp(-t / 0.13)
    thump = np.sin(sweep_phase(40 + 90 * np.exp(-t / 0.05))) * np.exp(-t / 0.09)
    return (crackle * 1.2 + thump) * envelope(len(t), attack=0.001)


def miss():
    """Soft falling fizzle when a circle leaves the top without a hit."""
    t = t_axis(0.3)
    freqs = 420 * np.exp(-t / 0.25)
    ph = sweep_phase(freqs)
    x = (np.sin(ph) + 0.2 * np.sin(3 * ph)) * np.exp(-t / 0.12)
    return x * envelope(len(t))


def dud():
    """Short muted click for pressing while a circle is still out."""
    t = t_axis(0.07)
    x = np.sign(np.sin(2 * np.pi * 120 * t)) * np.exp(-t / 0.018)
    return lowpass(x, 1800) * envelope(len(t), attack=0.001, release=0.01)


def notes(seq, wave_fn, decay):
    """Plays (frequency, seconds) pairs back to back."""
    parts = []
    for freq, dur in seq:
        t = t_axis(dur)
        parts.append(wave_fn(2 * np.pi * freq * t) * np.exp(-t / decay)
                     * envelope(len(t)))
    return np.concatenate(parts)


def square_soft(ph):
    return lowpass(np.sign(np.sin(ph)), 2500)


def triangle(ph):
    return 2 / np.pi * np.arcsin(np.sin(ph))


def game_over():
    """Descending F minor arpeggio, ending on a long low note."""
    x = notes([(523.25, 0.16), (415.30, 0.16), (349.23, 0.16),
               (261.63, 0.7)], square_soft, decay=0.25)
    return x * envelope(len(x), release=0.08)


def start():
    """Quick rising F minor arpeggio."""
    return notes([(349.23, 0.07), (415.30, 0.07), (523.25, 0.07),
                  (698.46, 0.22)], triangle, decay=0.12)


def main():
    os.makedirs(OUT, exist_ok=True)
    for mask, freq in FIRE_NOTES.items():
        save(f"fire_{mask}", fire(freq), 0.7)
    save("explosion", explosion(), 0.9)
    save("miss", miss(), 0.4)
    save("dud", dud(), 0.35)
    save("game_over", game_over(), 0.4)
    save("start", start(), 0.5)


if __name__ == "__main__":
    main()
