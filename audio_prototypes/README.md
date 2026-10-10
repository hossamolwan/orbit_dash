# Orbit Dash music prototypes

These are listening drafts only. Their rendered WAV files are not checked in;
they are outside `assets/audio/`, are not registered in `pubspec.yaml`, and are
not used by the game. The generator remains available to recreate them locally.

| File | Duration | Format | Size | Character |
| --- | ---: | --- | ---: | --- |
| `orbit_menu_prototype.wav` | 55.38 s | WAV, PCM 16-bit, stereo, 22.05 kHz | Regenerated locally | Spacious, warm ambient harmony with soft plucked highlights and no drum pulse. |
| `orbit_game_prototype.wav` | 36.92 s | WAV, PCM 16-bit, stereo, 22.05 kHz | Regenerated locally | 104 BPM, rounded bass and softened electronic percussion over the shared harmony. |

Both drafts use the same C major / A minor palette and the Cmaj9–Am9–Fmaj9–G6/9
progression. The gameplay track adds a restrained groove and bass movement;
the menu track leaves more space and changes its arrangement over its longer
loop. The shared tempo and harmony are intended to make a later crossfade feel
related. They are separate audition files; no transition has been added to the
game.

## Origin and rights

The compositions and rendered sounds are original Orbit Dash prototypes made
with the standard-library renderer in `build_prototypes.py`. It uses generated
wavetable voices, deterministic synthesized percussion, and a small algorithmic
room-reflection effect. It includes no third-party recordings, samples, or
streamed material. The drafts are intended for evaluation and commercial use
within Orbit Dash; they are not a claim of a final mastered soundtrack.

## Listening

- On Windows, open either WAV in VLC or Windows Media Player.
- On Android, copy the WAVs to the phone over USB and open them from a file
  manager or local music player. No network connection is needed.
- For a useful comparison, listen to both on the same headphones at a moderate
  volume. The game draft is 104 BPM; listen for whether its groove feels lively
  without becoming tense, and whether its harmonic color feels compatible with
  the calmer menu draft.

To regenerate these prototypes, run `python audio_prototypes/build_prototypes.py`
from the project root. This writes the WAVs into this directory, not the game's
asset directory.
