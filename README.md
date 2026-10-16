# Orbit Dash

Orbit Dash is a space arcade game built with Flutter. Move between orbital lanes, avoid asteroids, collect gems, and try to reach each stage's score target.

## About the Game

Each run takes place around a set of circular orbits. Choose a lane to move your ship, collect gems for points, and avoid incoming hazards. Progress through five stages, each with its own score target and number of orbits.

## Features

- Two to five orbits, depending on the selected stage.
- Select an orbit directly by tapping the play area.
- Dodge asteroids and collect gems while playing.
- Track the current score and save your best score locally.
- Five stages with different score targets; later stages unlock as you complete stages, and unlocked progress is saved locally.
- A temporary shield that absorbs one collision and lasts up to five seconds.
- Five locally saved achievements: First Steps, Gem Collector, Saved by the Shield, Orbit Explorer, and Orbital Master.
- Background music and separate sound effects, with independent controls whose settings are saved locally.
- Pause and resume gameplay; the game pauses when the app moves to the background.
- Responsive layouts for different screen sizes.

## Stages

| Stage | Name | Target score | Orbits |
| --- | --- | ---: | ---: |
| 1 | First Orbit | 10 points | 2 |
| 2 | Gem Hunter | 15 points | 3 |
| 3 | Asteroid Rush | 25 points | 4 |
| 4 | Cosmic Trial | 35 points | 5 |
| 5 | Orbital Master | 50 points | 5 |

Completing a stage unlocks the next stage. Previously unlocked stages remain available in the stage picker.

## Achievements

Achievements are saved on the device and can be viewed in the game:

| Achievement | Unlock condition |
| --- | --- |
| First Steps | Collect 10 gems in total. |
| Gem Collector | Collect 50 gems in total. |
| Saved by the Shield | Absorb an asteroid collision with the shield. |
| Orbit Explorer | Unlock Stage 4 by completing Stage 3. |
| Orbital Master | Complete Stage 5 successfully. |

## Built With

- [Flutter](https://flutter.dev/) for the app UI and game rendering.
- [Dart](https://dart.dev/) for the game and application code.
- [shared_preferences](https://pub.dev/packages/shared_preferences) for local scores, stage progress, achievements, and audio settings.
- [audioplayers](https://pub.dev/packages/audioplayers) for background music and sound effects.

## Getting Started

### Requirements

- Flutter SDK installed and available on your `PATH`.
- A Dart SDK compatible with the constraint in `pubspec.yaml` (provided with Flutter).
- A configured target device or emulator. Android Studio can be used to set up an Android emulator.

### Run the game

From the project directory, fetch dependencies and launch the app on a connected device or emulator:

```bash
flutter pub get
flutter run
```

## Testing

Run the automated tests and static analysis from the project directory:

```bash
flutter test
flutter analyze
```

## How to Play

1. Start a stage. The stage picker lets you choose any stage you have unlocked.
2. Tap the play area at the orbit you want to move to; the ship moves directly to that orbit.
3. Collect gems by reaching them. Gems add to your score and your lifetime gem total.
4. Avoid asteroids. A collision ends the run unless your temporary shield is active.
5. Collect the shield pickup to activate protection. It absorbs one collision, then is consumed; its protection lasts up to five seconds.
6. Reach the stage's target score to complete it and unlock the next stage. Use the pause control to pause, then resume when ready.

## Project Status

Current version: **1.2.0+3**

Orbit Dash is an actively developed Flutter game. This version includes five playable stages, local progress and achievement saving, audio controls, and pause/resume support.
