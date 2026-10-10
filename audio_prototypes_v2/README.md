# Orbit Dash music prototypes v2

These are audition drafts only. Their rendered WAV files are not checked in;
they are separate from the v1 prototypes and from `assets/audio/`, are not
registered in Flutter, and are not used by the game. The generator remains
available to recreate them locally.

| File | Duration | Format | Size |
| --- | ---: | --- | ---: |
| `orbit_menu_v2.wav` | 62.951 s | WAV, PCM 16-bit, stereo, 22.05 kHz | Regenerated locally |
| `orbit_game_v2.wav` | 47.213 s | WAV, PCM 16-bit, stereo, 22.05 kHz | Regenerated locally |

## New musical direction

Both sketches use 122 BPM and a D-major palette with Dmaj9–Aadd9–Bm7–Gmaj9
harmonies. The game track is a fuller arrangement of the same musical identity,
so a later crossfade can stay harmonically related. The menu is also rhythmic
and melodic, rather than ambient-only.

The lead is an eight-bar, syncopated call-and-response hook rendered as a
soft, multi-mode mallet sound, with selected octave accents. A round bass line,
layered chord voices, and a light kick/backbeat/shaker groove build the game
version. The arrangements change across sections and use small melodic and
rhythmic variations. The percussion is intentionally restrained and the output
has headroom; these are drafts for listening feedback, not final mastering.

## Origin and listening

The compositions and sounds are original, procedurally synthesized for Orbit
Dash by `build_prototypes.py`. No third-party recordings, samples, or streamed
material are used. The prototypes are intended for evaluation and commercial
use within Orbit Dash. The older `audio_prototypes/` files and generator were
not used as the basis for these arrangements and remain untouched.

- Windows: open either WAV in VLC or Windows Media Player.
- Android: copy the files to the phone over USB, then open them from a local
  file manager or music player. No network connection is needed.
- For comparison, use the same headphones and moderate system volume for both
  tracks. The gameplay sketch is 122 BPM; listen for a playful bounce, clear
  melody, comfortable treble, and whether the move from the menu's hook into the
  fuller groove feels like the same game.

Regenerate only these v2 WAVs with `python audio_prototypes_v2/build_prototypes.py`
from the project root. The script writes only into this directory.
