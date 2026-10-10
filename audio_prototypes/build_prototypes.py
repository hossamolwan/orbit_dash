"""Render two original Orbit Dash music sketches with the Python standard library."""

from array import array
import math
from pathlib import Path
import struct
import wave


ROOT = Path(__file__).resolve().parent
SAMPLE_RATE = 22050
BPM = 104
BEAT = 60 / BPM
BAR = BEAT * 4
TABLE_SIZE = 4096

# C major / A minor color: Cmaj9, Am9, Fmaj9, G6/9.
CHORDS = (
    ("C", 130.81, (0, 4, 7, 11, 14)),
    ("Am", 110.00, (0, 3, 7, 10, 14)),
    ("F", 87.31, (0, 4, 7, 11, 14)),
    ("G", 98.00, (0, 4, 7, 9, 14)),
)
PENTATONIC = (0, 2, 4, 7, 9, 12, 14, 16, 19)


def make_table(kind, harmonics):
    table = []
    for index in range(TABLE_SIZE):
        phase = 2 * math.pi * index / TABLE_SIZE
        if kind == "triangle":
            value = sum(
                ((-1) ** ((n - 1) // 2)) * math.sin(n * phase) / (n * n)
                for n in range(1, harmonics + 1, 2)
            )
        else:
            value = sum(
                ((-1) ** (n + 1)) * math.sin(n * phase) / (n**1.25)
                for n in range(1, harmonics + 1)
            )
        table.append(value)
    scale = max(abs(value) for value in table) or 1
    return tuple(value / scale for value in table)


TABLES = {
    (kind, harmonics): make_table(kind, harmonics)
    for kind in ("saw", "triangle")
    for harmonics in (3, 6, 12, 24)
}


def bandlimited_table(kind, frequency):
    harmonics = max(3, min(24, int(SAMPLE_RATE * 0.42 / frequency)))
    harmonics = min((3, 6, 12, 24), key=lambda value: abs(value - harmonics))
    return TABLES[(kind, harmonics)]


def midi_frequency(note):
    return 440 * 2 ** ((note - 69) / 12)


def add_voice(left, right, start, duration, frequency, *, kind, volume, pan,
              attack=0.02, release=0.15, detune=0.0, motion=0.0):
    start_frame = max(0, round(start * SAMPLE_RATE))
    frames = min(round(duration * SAMPLE_RATE), len(left) - start_frame)
    if frames <= 0:
        return
    table = bandlimited_table(kind, frequency)
    table_len = len(table)
    left_gain = math.sqrt((1 - pan) * 0.5)
    right_gain = math.sqrt((1 + pan) * 0.5)
    attack_frames = max(1, round(attack * SAMPLE_RATE))
    release_frames = max(1, round(release * SAMPLE_RATE))
    phase_a = phase_b = 0.0
    ratio_a = frequency * (1 - detune) / SAMPLE_RATE
    ratio_b = frequency * (1 + detune) / SAMPLE_RATE

    for offset in range(frames):
        remaining = frames - offset
        env = min(1.0, offset / attack_frames, remaining / release_frames)
        time = offset / SAMPLE_RATE
        wobble = 1 + motion * math.sin(2 * math.pi * 0.23 * time)
        phase_a = (phase_a + ratio_a * wobble) % 1
        phase_b = (phase_b + ratio_b * wobble) % 1
        index_a = phase_a * table_len
        index_b = phase_b * table_len
        ia = int(index_a)
        ib = int(index_b)
        sample_a = table[ia] + (table[(ia + 1) % table_len] - table[ia]) * (index_a - ia)
        sample_b = table[ib] + (table[(ib + 1) % table_len] - table[ib]) * (index_b - ib)
        sample = (sample_a + sample_b) * 0.5 * env * volume
        frame = start_frame + offset
        left[frame] += sample * left_gain
        right[frame] += sample * right_gain


def add_noise_hit(left, right, start, duration, *, volume, pan, seed, color="air"):
    # Deterministic filtered-noise percussion; the soft table-style smoothing
    # avoids the brittle white-noise edge of the first prototype set.
    start_frame = max(0, round(start * SAMPLE_RATE))
    frames = min(round(duration * SAMPLE_RATE), len(left) - start_frame)
    state = seed & 0x7FFFFFFF
    previous = 0.0
    left_gain = math.sqrt((1 - pan) * 0.5)
    right_gain = math.sqrt((1 + pan) * 0.5)
    for offset in range(frames):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        noise = state / 0x3FFFFFFF - 1
        if color == "air":
            previous += 0.16 * (noise - previous)
            sample = previous
        else:
            previous += 0.42 * (noise - previous)
            sample = noise - previous
        progress = offset / max(1, frames - 1)
        env = (1 - progress) ** (2.2 if color == "air" else 3.0)
        frame = start_frame + offset
        value = sample * env * volume
        left[frame] += value * left_gain
        right[frame] += value * right_gain


def add_kick(left, right, start, volume=0.14):
    start_frame = round(start * SAMPLE_RATE)
    frames = min(round(0.22 * SAMPLE_RATE), len(left) - start_frame)
    phase = 0.0
    for offset in range(max(0, frames)):
        time = offset / SAMPLE_RATE
        frequency = 92 - 43 * min(1.0, time / 0.16)
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        env = math.exp(-18 * time)
        sample = math.tanh(math.sin(phase) * 1.25) * env * volume
        frame = start_frame + offset
        left[frame] += sample * 0.707
        right[frame] += sample * 0.707


def add_room(left, right):
    # A light stereo early-reflection field, deliberately short and quiet.
    original_left = array("f", left)
    original_right = array("f", right)
    taps = ((0.113, 0.13), (0.197, 0.085), (0.311, 0.052), (0.421, 0.028))
    for delay, gain in taps:
        shift = round(delay * SAMPLE_RATE)
        for frame in range(shift, len(left)):
            left[frame] += original_right[frame - shift] * gain
            right[frame] += original_left[frame - shift] * gain


def chord_notes(chord_index, octave_shift=0):
    _, root, intervals = CHORDS[chord_index % len(CHORDS)]
    root_midi = round(69 + 12 * math.log2(root / 440)) + octave_shift
    return [root_midi + interval for interval in intervals]


def add_pad(left, right, bar_index, chord_index, *, arrangement=1.0):
    notes = chord_notes(chord_index, 0)
    start = bar_index * BAR
    duration = BAR * 1.07
    for voice, note in enumerate(notes):
        # Wide, soft-edged, detuned wavetable layers make a warm ensemble pad.
        add_voice(
            left, right, start, duration, midi_frequency(note), kind="saw",
            volume=0.032 * arrangement, pan=(-0.72 + voice * 0.34),
            attack=0.36, release=0.48, detune=0.004, motion=0.008,
        )
        add_voice(
            left, right, start, duration, midi_frequency(note + 12), kind="triangle",
            volume=0.011 * arrangement, pan=(0.62 - voice * 0.28),
            attack=0.55, release=0.55, detune=0.002, motion=0.006,
        )


def add_bell_motif(left, right, bar_index, chord_index, *, sparse=False):
    if sparse and bar_index % 2:
        return
    notes = chord_notes(chord_index, 12)
    rhythm = (0.5, 1.75, 2.5, 3.25) if bar_index % 4 in (0, 2) else (1.0, 2.75)
    for hit, beat_in_bar in enumerate(rhythm):
        interval = PENTATONIC[(bar_index + hit * 2 + chord_index) % len(PENTATONIC)]
        note = notes[min(2 + hit % 2, len(notes) - 1)] + interval
        start = bar_index * BAR + beat_in_bar * BEAT
        add_voice(
            left, right, start, 0.62, midi_frequency(note), kind="triangle",
            volume=0.032 if not sparse else 0.019,
            pan=(-0.4 if hit % 2 == 0 else 0.4), attack=0.008,
            release=0.48, detune=0.001,
        )


def add_menu_track():
    bars = 24
    total_frames = round(bars * BAR * SAMPLE_RATE)
    left = array("f", [0]) * total_frames
    right = array("f", [0]) * total_frames
    for bar in range(bars):
        chord = bar % 4
        section = bar // 8
        pad_level = (0.84, 1.0, 0.9)[section]
        add_pad(left, right, bar, chord, arrangement=pad_level)
        add_bell_motif(left, right, bar, chord, sparse=section == 1)
        # A very quiet, rounded low note gives the menu warmth without a beat.
        if bar % 2 == 0:
            root = chord_notes(chord, -12)[0]
            add_voice(
                left, right, bar * BAR, BAR * 0.8, midi_frequency(root),
                kind="triangle", volume=0.035, pan=0.0,
                attack=0.16, release=0.38,
            )
        # Soft air texture marks the start of each four-bar phrase.
        if bar % 4 == 0:
            add_noise_hit(
                left, right, bar * BAR, 0.9, volume=0.012,
                pan=(-0.25 if (bar // 4) % 2 else 0.25), seed=bar + 81,
            )
    add_room(left, right)
    write_wav("orbit_menu_prototype.wav", left, right)


def add_game_track():
    bars = 16
    total_frames = round(bars * BAR * SAMPLE_RATE)
    left = array("f", [0]) * total_frames
    right = array("f", [0]) * total_frames
    for bar in range(bars):
        chord = bar % 4
        section = bar // 4
        add_pad(left, right, bar, chord, arrangement=0.72 if section == 2 else 0.82)
        add_bell_motif(left, right, bar, chord, sparse=section == 2)

        notes = chord_notes(chord, -12)
        bass_pattern = (0, 2, 0, 3) if section % 2 == 0 else (0, 0, 2, 3)
        for beat_index, chord_tone in enumerate(bass_pattern):
            note = notes[chord_tone % len(notes)]
            start = bar * BAR + beat_index * BEAT
            add_voice(
                left, right, start, BEAT * 0.82, midi_frequency(note),
                kind="saw", volume=0.075, pan=0.0,
                attack=0.008, release=0.11, detune=0.001,
            )

        # Light kick/snare pulse at 104 BPM, with softened hats and small fills.
        for beat_index in (0, 2):
            add_kick(left, right, bar * BAR + beat_index * BEAT,
                     volume=0.11 if beat_index == 0 else 0.075)
        for beat_index in (1, 3):
            add_noise_hit(
                left, right, bar * BAR + beat_index * BEAT, 0.12,
                volume=0.027, pan=0.05, seed=bar * 7 + beat_index + 17,
                color="soft",
            )
        for eighth in range(8):
            if eighth % 2 == 0 and section == 2:
                continue
            start = bar * BAR + eighth * BEAT / 2
            add_noise_hit(
                left, right, start, 0.055,
                volume=0.008 if eighth % 2 == 0 else 0.014,
                pan=(-0.18 if eighth % 2 == 0 else 0.18),
                seed=bar * 13 + eighth + 201,
            )
        if bar % 4 == 3:
            add_noise_hit(
                left, right, bar * BAR + 3.5 * BEAT, 0.09,
                volume=0.018, pan=0.18, seed=bar + 300, color="soft",
            )
    add_room(left, right)
    write_wav("orbit_game_prototype.wav", left, right)


def write_wav(filename, left, right):
    path = ROOT / filename
    peak = max(max(map(abs, left)), max(map(abs, right)))
    normalization = 0.78 / peak if peak else 1.0
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        block = bytearray()
        for l_sample, r_sample in zip(left, right):
            # Conservative peak ceiling leaves headroom for phone playback.
            block.extend(struct.pack(
                "<hh",
                round(max(-0.88, min(0.88, l_sample * normalization)) * 32767),
                round(max(-0.88, min(0.88, r_sample * normalization)) * 32767),
            ))
        audio.writeframes(block)


if __name__ == "__main__":
    add_menu_track()
    add_game_track()
