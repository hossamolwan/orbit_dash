# Final gameplay and stability review

## Executive summary

The gameplay implementation is compact and internally coherent: a single
Flutter state object owns the survival run, a `Ticker` advances simulation,
shared helpers define angular/lane interactions, and a custom painter renders
the current state. The reviewed source and tests did not reveal a verified
gameplay defect, invalid run transition, or unbounded gameplay collection.

The existing widget tests exercise important run states and injected gameplay
events, but they do not drive the natural hazard spawn and movement loop for a
long run or validate frame behavior on representative Android hardware. These
are coverage and release-QA gaps, not evidence of a current failure.

**Verdict:** Gameplay & Stability can reasonably be considered complete as an
implementation milestone based on the reviewed code. Keep real-device play and
performance checks in final QA. The next logical review milestone is the
Economy/Shop area; payment integration and final release preparation remain
later work.

## Gameplay architecture overview

Gameplay is implemented in [lib/main.dart](../lib/main.dart):

- `OrbitGamePage` and `_OrbitGamePageState` own run state, score, orbit count,
  player lane and angle, hazards, gem and shield pickup state, and the ticker.
- `_tick` advances the simulation and handles hazard spawning/movement,
  collision, shield absorption, gem collection, scoring, and orbit unlocks.
- Top-level helpers such as `shortestAngularDistance`, `isLaneCollision`,
  `shouldCollectGem`, `hazardLaneForScore`, and `OrbitGeometry` centralize
  interaction and touch geometry rules.
- `TemporaryShield`, `playerSpeedForScore`,
  `hazardSpawnIntervalForScore`, `survivalOrbitCountForScore`, and
  `randomizedGemPlacement` hold focused gameplay rules.
- `_OrbitPainter` renders the current game state; it does not own simulation
  state. `_tapGame` maps touch coordinates through the same `OrbitGeometry`
  used by rendering.
- Run events are queued to the existing wallet, achievement, daily challenge,
  and statistics stores. This review did not re-audit those persistence
  subsystems.

## Run lifecycle and state review

`RunState` includes `ready`, `playing`, `paused`, `over`, and feature-screen
states. `_start` resets run-owned values and starts the ticker. `_pause` stops
it, `_resume` resets `_lastTick` before restarting it, and `_finish` stops it
and records the completed run once because it returns unless the state is
`playing`. `_returnToMenu` stops the ticker and clears active hazards and shield
state. Starting again resets the score and run counters.

The app lifecycle observer in `didChangeAppLifecycleState` pauses a playing run
on the first inactive/background transition, turns audio inactive, and queues
a progress flush. Repeated non-resumed lifecycle notifications do not queue
duplicate flushes until the app becomes active again. Returning to the app does
not silently resume play; the player remains paused and must select Resume.
`dispose` removes the observer, cancels the orbit notice timer, disposes the
ticker, removes the audio listener, and shuts down audio.

No verified invalid state transition, duplicate finish, stale ticker callback,
or post-disposal state update was found in these paths. UI callbacks for start,
resume, restart, and pause are only exposed in the corresponding states.

## Core mechanics review

- **Movement and input:** `_tick` advances the player angle using the
  score-derived speed. `_tapGame` selects a lane from shared orbit geometry and
  ignores taps that do not select a different valid lane. Geometry supports
  the implemented two-to-five orbit range, and a lane-count increase leaves
  the current lane valid.
- **Collision and collection:** `isLaneCollision` requires a matching lane
  and a shortest angular separation below `0.16` radians. Gem and shield
  pickup checks use the same lane condition and a `0.12` radian angular
  threshold. The shield absorbs one collision and is consumed; without an
  active shield, the collision ends the run. The compared angles are
  normalized or passed through shortest-distance logic, including wraparound.
- **Hazards:** `_tick` schedules a hazard at a score-dependent interval,
  advances its angle, checks collision, and removes absorbed or expired
  hazards. The lane helper keeps hazards off the player's current lane when
  there are more than two lanes. With two lanes it can select the current
  lane, while spawning the hazard at an angular offset; this is an observed
  design choice and is not demonstrated by the reviewed code to create an
  unfair collision.
- **Gems and shield:** One gem is active at a time. Collection increments the
  score, relocates the gem, and queues associated progression events. The next
  gem avoids a `0.65` radian window around the current player angle by moving
  to the opposite angle if necessary. Shield pickups are single and spawn
  after a randomized interval in the 12â€“20 second range when no shield or
  pickup is active. The five-second timer advances only during active ticker
  time, so pause freezes shield duration.
- **Orbit progression:** Survival unlocks at scores 10, 25, and 45, advancing
  through two to five lanes. The same thresholds are exercised by widget tests.

No concrete mechanic defect was verified in these paths.

## Difficulty and progression review

`playerSpeedForScore` is monotonic for nonnegative score and approaches its
maximum of `2.75`. `hazardSpawnIntervalForScore` decreases from `2.0` seconds
to a floor of `0.95` seconds. Both formulas clamp negative inputs through
`math.max(0, score)`. Orbit thresholds are ordered and produce a maximum of
five lanes. The tests check monotonicity, high-score bounds, threshold values,
and randomized gem placement bounds.

The inspected formulas contain no mathematical inconsistency or unbounded
difficulty growth. Whether the resulting challenge is enjoyable is a playtest
question and was not inferred from the formulas alone.

## Game loop performance and stability

The ticker clamps each simulation step to at most 50 ms, which limits large
single-step jumps after a delayed frame. Each active tick rebuilds the game
state and painter inputs and creates a temporary absorbed-hazards list. The
hazard list is pruned as hazards are absorbed or complete a relative turn;
spawn intervals have a positive lower bound. The source therefore does not
show an unbounded hazard accumulation path under normal ticking.

The painter reports `shouldRepaint => true`, so it repaints whenever its
rendering inputs are updated. No profiling data was collected, and the
repository does not establish frame rates on target devices; a measurable
performance problem was not verified. Device profiling belongs in final QA if
playtesting reveals frame drops.

## App lifecycle and interruption review

Backgrounding during play changes the run to paused and stops ticker-driven
simulation. Foregrounding reactivates audio but leaves the run paused. Repeated
background notifications are deduplicated by `_appIsActive`; progress flushes
are chained through `_backgroundProgressFlushes`. The ticker is disposed with
the widget, and the audio initialization continuation checks `mounted` before
applying its result.

The widget tests cover background pause/flush behavior and audio state
transitions. They do not cover every platform-specific interruption or actual
device suspension behavior. No remaining lifecycle defect specific to
gameplay was verified.

## Gameplay persistence integration findings

Score and orbit state are updated in the simulation before their associated
feature writes are queued. A collected gem queues wallet credit with a
run-scoped pickup ID, achievement progress, and daily challenge progress. Run
completion queues the survival statistic and loss record; the best score is
queued only for a new record. Lifecycle flushing waits for queued writes and
store flushes through `_flushProgress`.

The widget suite covers a queued best-score flush, background flush ordering,
gem progress across retry/recreated pages, and run/shield/loss statistics.
No gameplay transition that demonstrably loses or duplicates an event was
found. Persistence redesign was outside this review.

## Test coverage and gaps

Relevant coverage is primarily in [test/widget_test.dart](../test/widget_test.dart):

- Helper tests cover angular wraparound, strict collision thresholds, lane
  rules, shield duration/absorption, hazard lifetime, difficulty bounds,
  orbit thresholds, randomized placement, and orbit geometry.
- Widget tests cover run start, pause/resume/restart, game over/retry, shield
  pickup/expiry/absorption, orbit unlocks through 45 gems, continuation beyond
  50 gems, background pause/flush, audio transitions, and compact layouts.
- [test/progression_features_widget_test.dart](../test/progression_features_widget_test.dart)
  covers skin and statistics flows. It supplements gameplay integration
  coverage but is not a substitute for driving the natural simulation loop.
- [test/ui_polish_widget_test.dart](../test/ui_polish_widget_test.dart)
  covers selected HUD and achievement presentation behavior.

Remaining useful coverage gaps:

1. A deterministic sustained run that exercises naturally spawned hazards,
   their angular movement and expiration, and transitions at higher scores.
2. End-to-end lane switching under active simulation near the collision and
   collection thresholds, including rapid inputs and newly unlocked lanes.
3. Platform/device QA for interruption behavior and frame pacing on the
   intended Android target.

These are recommended coverage additions, not failures demonstrated by the
current implementation. Tests were inspected but not run for this audit.

## Prioritized findings

### Verified issues

None identified in the reviewed gameplay implementation.

### Observations and potential risks

| Severity | Observation | Evidence and impact | Direction | Regression test |
| --- | --- | --- | --- | --- |
| Informational | Natural hazard simulation has limited automated integration coverage. | Existing tests inject hazards for collision behavior; helper tests validate lane and lifetime rules, but do not sustain natural spawning/movement across a run. This leaves future regressions in the integrated spawn/update loop less directly guarded. | Add deterministic simulation coverage when extending gameplay tests. | Yes |
| Informational | Device-specific frame pacing and interruptions were not established by source review. | A clamped ticker step and bounded hazard lifetime are present, but no target-device profiling or interruption test can establish real-world frame performance. | Include representative Android play and lifecycle checks in final QA. | Device QA |

No Critical, High, Medium, or Low severity defect was verified. The observations
above are not current gameplay failures.

## Recommended next milestones

1. Move to an Economy/Shop review, keeping payment integration separate until
   its backend and platform prerequisites are ready.
2. Add the focused natural-hazard integration coverage when gameplay code is
   next changed; it does not justify reopening the completed gameplay
   implementation milestone by itself.
3. Reserve Android device play, interruption, and performance checks for Final
   QA & Release Preparation.

No additional gameplay implementation milestone is warranted by the reviewed
evidence. Purchase enablement and release readiness remain deferred to their
respective roadmap phases.

## Final verdict

The reviewed Gameplay & Stability implementation is reasonably ready to be
considered closed. No concrete gameplay or stability defect was found, and the
current test suite covers the main state transitions and mechanic helpers.
Closeout should retain the stated natural-hazard coverage gap and defer actual
device performance and interruption validation to final QA.
