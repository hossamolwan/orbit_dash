"""Generate the original, local Orbit Dash audio assets using Python's stdlib."""

import math
import os
import random
import struct
import wave


SAMPLE_RATE = 22050
OUTPUT_DIR = os.path.join("assets", "audio")


def write_wav(name, samples):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_DIR, name)
    with wave.open(path, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        audio.writeframes(b"".join(
            struct.pack("<h", round(max(-1.0, min(1.0, value)) * 32767))
            for value in samples
        ))


def music_sample(t, game):
    beat = 0.5 if game else 1.0
    bar = beat * 4
    chord_roots = (110.0, 130.81, 98.0, 146.83)
    chord_index = int(t / bar) % len(chord_roots)
    root = chord_roots[chord_index]
    phase_in_bar = t % bar
    pad = sum(
        math.sin(2 * math.pi * root * ratio * t + phase)
        for ratio, phase in ((1, 0.1), (1.5, 0.8), (2, 1.7))
    ) / 3
    pad *= 0.105 if game else 0.13

    step = beat / (2 if game else 1)
    step_index = int(t / step)
    scale = (1, 1.1892, 1.3348, 1.4983, 1.7818, 2)
    note = root * 2 * scale[(step_index * 3 + chord_index) % len(scale)]
    note_age = (t % step) / step
    pluck = math.sin(2 * math.pi * note * t) * math.exp(-5.0 * note_age)
    pluck *= 0.075 if game else 0.045

    if game:
        bass_phase = (t % beat) / beat
        bass = math.sin(2 * math.pi * root * t) * (0.5 + 0.5 * math.cos(2 * math.pi * bass_phase))
        return pad + pluck + bass * 0.10

    shimmer = math.sin(2 * math.pi * root * 8 * t) * 0.018
    breathing = 0.88 + 0.12 * math.sin(2 * math.pi * t / 8)
    return (pad + pluck + shimmer) * breathing


def make_music(name, game):
    duration = 16.0
    total = int(SAMPLE_RATE * duration)
    fade_samples = int(SAMPLE_RATE * 0.04)
    samples = []
    for index in range(total):
        t = index / SAMPLE_RATE
        value = music_sample(t, game)
        edge = min(1.0, index / fade_samples, (total - 1 - index) / fade_samples)
        samples.append(value * max(0.0, edge))
    write_wav(name, samples)


def make_effect(name, start_hz, end_hz, duration, kind="tone", seed=1):
    total = int(SAMPLE_RATE * duration)
    rng = random.Random(seed)
    phase = 0.0
    samples = []
    for index in range(total):
        t = index / SAMPLE_RATE
        progress = index / max(1, total - 1)
        frequency = start_hz + (end_hz - start_hz) * progress
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        envelope = math.sin(math.pi * progress) ** 0.7
        if kind == "noise":
            signal = rng.uniform(-1.0, 1.0) * 0.55 + math.sin(phase) * 0.45
        elif kind == "chord":
            signal = (math.sin(phase) + 0.45 * math.sin(phase * 1.5)) / 1.45
        else:
            signal = math.sin(phase) * 0.75 + math.sin(phase * 2.01) * 0.25
        samples.append(signal * envelope * 0.42)
    write_wav(name, samples)


make_music("orbit_menu.wav", game=False)
make_music("orbit_game.wav", game=True)
make_effect("orbit_switch.wav", 520, 860, 0.12, seed=2)
make_effect("gem_collect.wav", 720, 1450, 0.24, kind="chord", seed=3)
make_effect("collision.wav", 240, 54, 0.42, kind="noise", seed=4)
make_effect("start_run.wav", 330, 660, 0.28, kind="chord", seed=5)
make_effect("pause.wav", 600, 310, 0.18, seed=6)
make_effect("resume.wav", 310, 620, 0.18, seed=7)
