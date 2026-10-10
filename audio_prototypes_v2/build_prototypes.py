"""Render a fresh, original cartoon-arcade soundtrack sketch for Orbit Dash."""

from array import array
import math
from pathlib import Path
import struct
import wave


ROOT = Path(__file__).resolve().parent
RATE = 22050
BPM = 122
BEAT = 60 / BPM
BAR = 4 * BEAT
TABLE_SIZE = 2048

# A different, brighter D-major progression from v1.
CHORDS = (
    (146.83, (0, 4, 7, 11, 14)),       # Dmaj9
    (110.00, (0, 4, 7, 14)),           # Aadd9
    (123.47, (0, 3, 7, 10, 14)),       # Bm7
    (98.00, (0, 4, 7, 11, 14)),        # Gmaj9
)

# Each bar has its own rhythm and contour. The eight-bar phrase has a call,
# answer, lifted repeat and turnaround rather than a short arpeggio loop.
HOOK = (
    ((0.00, 74, .42), (.75, 78, .32), (1.50, 81, .58), (2.50, 78, .36), (3.25, 76, .42)),
    ((.25, 74, .32), (1.00, 71, .42), (1.75, 76, .48), (2.75, 78, .32), (3.50, 81, .30)),
    ((0.00, 69, .40), (.75, 74, .34), (1.50, 78, .52), (2.50, 76, .38), (3.00, 74, .50)),
    ((.50, 71, .36), (1.25, 74, .40), (2.00, 76, .38), (2.75, 73, .42), (3.50, 74, .36)),
    ((0.00, 78, .40), (.75, 81, .34), (1.50, 83, .56), (2.50, 81, .36), (3.25, 78, .42)),
    ((.25, 76, .32), (1.00, 78, .40), (1.75, 81, .50), (2.75, 78, .34), (3.50, 74, .38)),
    ((0.00, 71, .38), (.75, 74, .34), (1.50, 78, .50), (2.50, 81, .38), (3.25, 78, .42)),
    ((0.00, 76, .34), (.75, 74, .36), (1.75, 71, .42), (2.50, 69, .34), (3.50, 74, .42)),
)


def make_wave(kind, partial_count):
    result = []
    for i in range(TABLE_SIZE):
        phase = 2 * math.pi * i / TABLE_SIZE
        if kind == "triangle":
            value = sum(
                ((-1) ** ((n - 1) // 2)) * math.sin(n * phase) / n**2
                for n in range(1, partial_count + 1, 2)
            )
        else:
            # Rounded, band-limited saw: rich harmonics without a sharp edge.
            value = sum(
                ((-1) ** (n + 1)) * math.sin(n * phase) / n**1.35
                for n in range(1, partial_count + 1)
            )
        result.append(value)
    peak = max(map(abs, result)) or 1
    return tuple(x / peak for x in result)


WAVES = {
    (kind, count): make_wave(kind, count)
    for kind in ("triangle", "saw")
    for count in (3, 6, 12, 24)
}


def note_hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def wave_for(kind, frequency):
    needed = max(3, min(24, int(RATE * .43 / frequency)))
    count = min((3, 6, 12, 24), key=lambda option: abs(option - needed))
    return WAVES[(kind, count)]


def pan_gains(pan):
    return math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)


def add_voice(left, right, start, duration, frequency, *, kind, volume, pan,
              attack=.01, release=.1, detune=0.0):
    first = max(0, round(start * RATE))
    length = min(round(duration * RATE), len(left) - first)
    if length <= 0:
        return
    table = wave_for(kind, frequency)
    size = len(table)
    gain_l, gain_r = pan_gains(pan)
    attack_frames = max(1, round(attack * RATE))
    release_frames = max(1, round(release * RATE))
    phase_l = phase_r = 0.0
    step_l = frequency * (1 - detune) / RATE
    step_r = frequency * (1 + detune) / RATE
    for offset in range(length):
        fade_in = min(1.0, offset / attack_frames)
        fade_out = min(1.0, (length - offset) / release_frames)
        envelope = fade_in * fade_out
        phase_l = (phase_l + step_l) % 1
        phase_r = (phase_r + step_r) % 1
        index_l, index_r = phase_l * size, phase_r * size
        i_l, i_r = int(index_l), int(index_r)
        sample_l = table[i_l] + (table[(i_l + 1) % size] - table[i_l]) * (index_l - i_l)
        sample_r = table[i_r] + (table[(i_r + 1) % size] - table[i_r]) * (index_r - i_r)
        frame = first + offset
        left[frame] += sample_l * envelope * volume * gain_l
        right[frame] += sample_r * envelope * volume * gain_r


def add_mallet(left, right, start, duration, frequency, *, volume, pan, brightness=1.0):
    """Soft marimba-like bar made from inharmonic, quickly decaying modes."""
    first = max(0, round(start * RATE))
    length = min(round(duration * RATE), len(left) - first)
    if length <= 0:
        return
    gain_l, gain_r = pan_gains(pan)
    modes = ((1.0, 1.0, .36), (2.76, .19, .16), (5.40, .055, .075), (8.93, .014, .035))
    for offset in range(length):
        t = offset / RATE
        # A rounded strike followed by a natural, non-uniform modal decay.
        strike = 1 - math.exp(-t * 105)
        sample = sum(
            weight * math.exp(-t / max(.025, decay * brightness))
            * math.sin(2 * math.pi * frequency * ratio * t)
            for ratio, weight, decay in modes
        )
        sample *= strike * volume
        frame = first + offset
        left[frame] += sample * gain_l
        right[frame] += sample * gain_r


def add_soft_percussion(left, right, start, duration, *, volume, pan, seed, lowpass=.32):
    first = max(0, round(start * RATE))
    length = min(round(duration * RATE), len(left) - first)
    state = seed & 0x7FFFFFFF
    smooth = 0.0
    gain_l, gain_r = pan_gains(pan)
    for offset in range(length):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        raw = state / 0x3FFFFFFF - 1
        smooth += lowpass * (raw - smooth)
        envelope = (1 - offset / max(1, length)) ** 2.4
        value = smooth * envelope * volume
        frame = first + offset
        left[frame] += value * gain_l
        right[frame] += value * gain_r


def add_kick(left, right, start, volume):
    first = round(start * RATE)
    length = min(round(.20 * RATE), len(left) - first)
    phase = 0.0
    for offset in range(max(0, length)):
        t = offset / RATE
        phase += 2 * math.pi * (88 - 38 * min(1, t / .15)) / RATE
        envelope = math.exp(-17 * t)
        # Soft saturation rounds the transient instead of producing a hard click.
        sample = math.tanh(math.sin(phase) * 1.12) * envelope * volume
        frame = first + offset
        left[frame] += sample * .707
        right[frame] += sample * .707


def add_hook(left, right, bar_index, *, menu=False, variation=0):
    events = HOOK[bar_index % len(HOOK)]
    for hit, (beat_offset, note, duration) in enumerate(events):
        if menu and hit in (1, 3) and bar_index % 4 in (1, 2):
            continue
        if variation and hit == 4:
            note += 2 if bar_index % 2 == 0 else -2
        start = bar_index * BAR + beat_offset * BEAT
        brightness = .82 if menu else 1.0
        add_mallet(
            left, right, start, duration * BEAT, note_hz(note),
            volume=.11 if menu else .095, pan=(-.28 if hit % 2 == 0 else .28),
            brightness=brightness,
        )
        # A soft, short synth accent answers selected mallet notes in gameplay.
        if not menu and hit in (1, 4):
            add_voice(
                left, right, start, .20 * BEAT, note_hz(note + 12),
                kind="triangle", volume=.025, pan=.18 if hit == 1 else -.18,
                attack=.004, release=.13,
            )


def add_chord_bed(left, right, bar_index, chord_index, *, level):
    root, intervals = CHORDS[chord_index % 4]
    root_note = round(69 + 12 * math.log2(root / 440))
    start = bar_index * BAR
    for voice, interval in enumerate(intervals):
        note = root_note + interval
        add_voice(
            left, right, start, BAR * 1.06, note_hz(note), kind="saw",
            volume=.020 * level, pan=-.62 + voice * .31,
            attack=.10, release=.18, detune=.003,
        )
        add_voice(
            left, right, start, BAR * 1.06, note_hz(note + 12), kind="triangle",
            volume=.008 * level, pan=.56 - voice * .26,
            attack=.15, release=.22, detune=.0015,
        )


def bass_note(chord_index, degree):
    root, intervals = CHORDS[chord_index % 4]
    midi = round(69 + 12 * math.log2(root / 440)) - 12
    return midi + intervals[degree % len(intervals)]


def add_bass_pulse(left, right, bar_index, chord_index, *, game):
    pattern = (0, 2, 0, 3) if bar_index % 2 == 0 else (0, 1, 2, 3)
    for beat_index, degree in enumerate(pattern):
        if not game and beat_index in (1, 3):
            continue
        start = bar_index * BAR + beat_index * BEAT
        add_voice(
            left, right, start, BEAT * (.66 if game else .78),
            note_hz(bass_note(chord_index, degree)), kind="triangle",
            volume=.085 if game else .047, pan=0,
            attack=.008, release=.10 if game else .18,
        )


def add_room(left, right):
    dry_l, dry_r = array("f", left), array("f", right)
    for seconds, gain in ((.092, .11), (.163, .07), (.247, .04)):
        shift = round(seconds * RATE)
        for i in range(shift, len(left)):
            left[i] += dry_r[i - shift] * gain
            right[i] += dry_l[i - shift] * gain


def write_wave(name, left, right):
    peak = max(max(map(abs, left)), max(map(abs, right))) or 1
    scale = .78 / peak
    with wave.open(str(ROOT / name), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        pcm = bytearray()
        for l_sample, r_sample in zip(left, right):
            pcm.extend(struct.pack(
                "<hh",
                round(max(-.88, min(.88, l_sample * scale)) * 32767),
                round(max(-.88, min(.88, r_sample * scale)) * 32767),
            ))
        output.writeframes(pcm)


def render_menu():
    bars = 32
    frames = round(bars * BAR * RATE)
    left, right = array("f", [0]) * frames, array("f", [0]) * frames
    for bar in range(bars):
        chord = bar % 4
        section = bar // 8
        add_chord_bed(left, right, bar, chord, level=(.78, 1.0, .84, .96)[section])
        add_bass_pulse(left, right, bar, chord, game=False)
        add_hook(left, right, bar, menu=True, variation=section % 2)
        # A tiny, soft shaker marks phrases; it is absent from most beats.
        if bar % 2 == 1:
            add_soft_percussion(
                left, right, bar * BAR + 3 * BEAT, .075,
                volume=.010, pan=.18 if bar % 4 else -.18, seed=bar + 29,
                lowpass=.20,
            )
    add_room(left, right)
    write_wave("orbit_menu_v2.wav", left, right)


def render_game():
    bars = 24
    frames = round(bars * BAR * RATE)
    left, right = array("f", [0]) * frames, array("f", [0]) * frames
    for bar in range(bars):
        chord = bar % 4
        section = bar // 8
        add_chord_bed(left, right, bar, chord, level=.72 if section == 1 else .88)
        add_bass_pulse(left, right, bar, chord, game=True)
        add_hook(left, right, bar, variation=section % 2)

        # Bouncy, light backbeat with phrase-level omissions and fills.
        for beat_index in (0, 2):
            if section == 1 and bar % 4 == 3 and beat_index == 2:
                continue
            add_kick(
                left, right, bar * BAR + beat_index * BEAT,
                .095 if beat_index == 0 else .065,
            )
        for beat_index in (1, 3):
            add_soft_percussion(
                left, right, bar * BAR + beat_index * BEAT, .105,
                volume=.023, pan=.04, seed=bar * 5 + beat_index + 101,
                lowpass=.26,
            )
        for eighth in range(8):
            if section == 1 and eighth % 2 == 0:
                continue
            if section == 2 and eighth in (0, 4):
                continue
            add_soft_percussion(
                left, right, bar * BAR + eighth * BEAT / 2, .045,
                volume=.008 if eighth % 2 == 0 else .012,
                pan=-.15 if eighth % 2 == 0 else .15,
                seed=bar * 11 + eighth + 501, lowpass=.22,
            )
        if bar % 4 == 3:
            add_soft_percussion(
                left, right, bar * BAR + 3.5 * BEAT, .08,
                volume=.015, pan=.12, seed=bar + 811, lowpass=.30,
            )
    add_room(left, right)
    write_wave("orbit_game_v2.wav", left, right)


if __name__ == "__main__":
    render_menu()
    render_game()
