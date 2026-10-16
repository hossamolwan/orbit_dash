import 'dart:async';
import 'dart:math' as math;

import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const OrbitDashApp());

class OrbitDashApp extends StatelessWidget {
  const OrbitDashApp({super.key, this.audioController});

  final GameAudioController? audioController;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit Dash',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff070b18),
      colorScheme: const ColorScheme.dark(primary: Color(0xff55e7ff)),
    ),
    home: OrbitGamePage(audioController: audioController),
  );
}

enum RunState {
  ready,
  selectingStage,
  playing,
  paused,
  over,
  stageComplete,
  gameComplete,
  achievements,
}

/// Deterministic controls and observations for game-cycle widget tests.
class OrbitGameTestDriver {
  OrbitGameTestDriver({this.achievementPreferencesLoader});

  final Future<SharedPreferences> Function()? achievementPreferencesLoader;

  late void Function() _placeShieldAtPlayer;
  late void Function() _placeHazardAtPlayer;
  late void Function() _placeGemAtPlayer;
  late void Function() _moveGemAwayFromPlayer;
  late bool Function() _readShieldActive;
  late Duration Function() _readShieldRemaining;
  late int Function() _readHazardCount;
  late int Function() _readScore;
  late RunState Function() _readRunState;
  late int Function() _readTotalGems;
  late bool Function(AchievementId id) _readAchievementUnlocked;
  late Future<void> Function() _flushAchievements;

  bool get shieldActive => _readShieldActive();
  Duration get shieldRemaining => _readShieldRemaining();
  int get hazardCount => _readHazardCount();
  int get score => _readScore();
  RunState get runState => _readRunState();
  int get totalGems => _readTotalGems();
  bool achievementUnlocked(AchievementId id) => _readAchievementUnlocked(id);
  Future<void> flushAchievements() => _flushAchievements();

  void placeShieldAtPlayer() => _placeShieldAtPlayer();
  void placeHazardAtPlayer() => _placeHazardAtPlayer();
  void placeGemAtPlayer() => _placeGemAtPlayer();
  void moveGemAwayFromPlayer() => _moveGemAwayFromPlayer();

  void _attach({
    required void Function() placeShieldAtPlayer,
    required void Function() placeHazardAtPlayer,
    required void Function() placeGemAtPlayer,
    required void Function() moveGemAwayFromPlayer,
    required bool Function() readShieldActive,
    required Duration Function() readShieldRemaining,
    required int Function() readHazardCount,
    required int Function() readScore,
    required RunState Function() readRunState,
    required int Function() readTotalGems,
    required bool Function(AchievementId id) readAchievementUnlocked,
    required Future<void> Function() flushAchievements,
  }) {
    _placeShieldAtPlayer = placeShieldAtPlayer;
    _placeHazardAtPlayer = placeHazardAtPlayer;
    _placeGemAtPlayer = placeGemAtPlayer;
    _moveGemAwayFromPlayer = moveGemAwayFromPlayer;
    _readShieldActive = readShieldActive;
    _readShieldRemaining = readShieldRemaining;
    _readHazardCount = readHazardCount;
    _readScore = readScore;
    _readRunState = readRunState;
    _readTotalGems = readTotalGems;
    _readAchievementUnlocked = readAchievementUnlocked;
    _flushAchievements = flushAchievements;
  }
}

class StageDefinition {
  const StageDefinition({
    required this.number,
    required this.name,
    required this.targetScore,
    required this.orbitCount,
  });

  final int number;
  final String name;
  final int targetScore;
  final int orbitCount;
}

const List<StageDefinition> orbitStages = [
  StageDefinition(
    number: 1,
    name: 'First Orbit',
    targetScore: 10,
    orbitCount: 2,
  ),
  StageDefinition(
    number: 2,
    name: 'Gem Hunter',
    targetScore: 15,
    orbitCount: 3,
  ),
  StageDefinition(
    number: 3,
    name: 'Asteroid Rush',
    targetScore: 25,
    orbitCount: 4,
  ),
  StageDefinition(
    number: 4,
    name: 'Cosmic Trial',
    targetScore: 35,
    orbitCount: 5,
  ),
  StageDefinition(
    number: 5,
    name: 'Orbital Master',
    targetScore: 50,
    orbitCount: 5,
  ),
];

class StageCompletionGate {
  bool _completed = false;

  bool completeIfReached(int score, StageDefinition stage) {
    if (_completed || score < stage.targetScore) return false;
    _completed = true;
    return true;
  }

  void reset() => _completed = false;
}

class StageProgressStore {
  static const preferenceKey = 'orbit_dash_unlocked_stage';

  Future<int> loadUnlockedStage() async {
    final preferences = await SharedPreferences.getInstance();
    return _storedStage(preferences);
  }

  Future<void> unlockThrough(int stageNumber) async {
    final preferences = await SharedPreferences.getInstance();
    final current = _storedStage(preferences);
    final requested = _validStage(stageNumber);
    if (requested > current) {
      await preferences.setInt(preferenceKey, requested);
    }
  }

  int _validStage(int? value) =>
      value == null || value < 1 || value > orbitStages.length ? 1 : value;

  int _storedStage(SharedPreferences preferences) {
    try {
      return _validStage(preferences.getInt(preferenceKey));
    } on TypeError {
      return 1;
    }
  }
}

const double _fullTurn = math.pi * 2;

double shortestAngularDistance(double first, double second) {
  final difference = (first - second).abs() % _fullTurn;
  return math.min(difference, _fullTurn - difference);
}

bool isAngularCollision(double first, double second) =>
    shortestAngularDistance(first, second) < 0.16;

bool isLaneCollision({
  required int playerLane,
  required int hazardLane,
  required double playerAngle,
  required double hazardAngle,
}) => playerLane == hazardLane && isAngularCollision(playerAngle, hazardAngle);

bool shouldCollectGem({
  required int playerLane,
  required int gemLane,
  required double playerAngle,
  required double gemAngle,
}) =>
    playerLane == gemLane &&
    shortestAngularDistance(playerAngle, gemAngle) < 0.12;

bool shouldCollectShield({
  required int playerLane,
  required int shieldLane,
  required double playerAngle,
  required double shieldAngle,
}) => shouldCollectGem(
  playerLane: playerLane,
  gemLane: shieldLane,
  playerAngle: playerAngle,
  gemAngle: shieldAngle,
);

/// Countdown state for the single-use, five-second shield.
class TemporaryShield {
  static const duration = Duration(seconds: 5);

  Duration _remaining = Duration.zero;

  bool get isActive => _remaining > Duration.zero;
  Duration get remaining => _remaining;

  bool activate() {
    if (isActive) return false;
    _remaining = duration;
    return true;
  }

  void advance(Duration elapsed) {
    if (!isActive || elapsed <= Duration.zero) return;
    _remaining -= elapsed;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
  }

  bool absorbCollision() {
    if (!isActive) return false;
    _remaining = Duration.zero;
    return true;
  }

  void reset() => _remaining = Duration.zero;
}

enum ShieldCollisionResponse { noCollision, absorbed, fatal }

ShieldCollisionResponse shieldCollisionResponse(
  TemporaryShield shield, {
  required bool collision,
}) {
  if (!collision) return ShieldCollisionResponse.noCollision;
  return shield.absorbCollision()
      ? ShieldCollisionResponse.absorbed
      : ShieldCollisionResponse.fatal;
}

int nextOrbitLane(int lane, int orbitCount) => (lane + 1) % orbitCount;

int hazardLaneForScore(int score, int playerLane, int orbitCount) {
  if (orbitCount == 2) {
    return score % 3 == 2 ? 1 - playerLane : score % 2;
  }
  return (playerLane + 1 + score % (orbitCount - 1)) % orbitCount;
}

/// The shared geometry used by both orbit rendering and touch selection.
class OrbitGeometry {
  const OrbitGeometry({required this.center, required this.radii});

  factory OrbitGeometry.forSize(Size size) {
    return OrbitGeometry.forSizeAndCount(size, orbitCount: 2);
  }

  factory OrbitGeometry.forSizeAndCount(Size size, {required int orbitCount}) {
    assert(orbitCount >= 2 && orbitCount <= 5);
    final outerRadius = size.width * (orbitCount == 2 ? 0.34 : 0.43);
    final innerRadius = orbitCount == 2
        ? outerRadius * 0.72
        : outerRadius * 0.18;
    return OrbitGeometry(
      center: Offset(size.width / 2, size.height / 2 + size.height * 0.035),
      radii: List<double>.unmodifiable(
        List<double>.generate(
          orbitCount,
          (index) =>
              innerRadius +
              (outerRadius - innerRadius) * index / (orbitCount - 1),
        ),
      ),
    );
  }

  final Offset center;
  final List<double> radii;
  double get innerRadius => radii.first;
  double get outerRadius => radii.last;
  double get touchTolerance => radii.length == 2
      ? math.min(18.0, (outerRadius - innerRadius) / 2)
      : math.min(18.0, (outerRadius - innerRadius) / (radii.length - 1) / 2);

  double radiusForLane(int lane) => radii[lane];

  int? laneAt(Offset position) {
    final distance = (position - center).distance;
    var closestLane = 0;
    var closestDistance = (distance - radii.first).abs();
    var secondClosestDistance = double.infinity;
    for (var lane = 1; lane < radii.length; lane++) {
      final laneDistance = (distance - radii[lane]).abs();
      if (laneDistance < closestDistance) {
        secondClosestDistance = closestDistance;
        closestDistance = laneDistance;
        closestLane = lane;
      } else if (laneDistance < secondClosestDistance) {
        secondClosestDistance = laneDistance;
      }
    }
    if ((secondClosestDistance - closestDistance).abs() < 0.0001 ||
        closestDistance > touchTolerance) {
      return null;
    }
    return closestLane;
  }
}

int laneAfterOrbitTouch(
  int currentLane,
  OrbitGeometry geometry,
  Offset position,
) => geometry.laneAt(position) ?? currentLane;

bool hazardLifetimeExpired(double relativeAngleTravel) =>
    relativeAngleTravel >= _fullTurn;

double playerSpeedForScore(int score) => 1.55 + math.min(score * 0.035, 1.5);

double hazardSpawnIntervalForScore(int score) =>
    math.max(0.85, 2.0 - score * 0.025);

class OrbitGamePage extends StatefulWidget {
  const OrbitGamePage({
    super.key,
    this.audioController,
    this.stages = orbitStages,
    this.testDriver,
  }) : assert(stages.length >= 1 && stages.length <= 5);

  final GameAudioController? audioController;
  final List<StageDefinition> stages;
  final OrbitGameTestDriver? testDriver;

  @override
  State<OrbitGamePage> createState() => _OrbitGamePageState();
}

class _OrbitGamePageState extends State<OrbitGamePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _orbitCanvasKey = GlobalKey();
  late final GameAudioController _audio;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  RunState _state = RunState.ready;
  int _score = 0;
  int _best = 0;
  int _currentStageIndex = 0;
  int _highestUnlockedStage = 1;
  bool _stageProgressLoaded = false;
  final StageProgressStore _stageProgressStore = StageProgressStore();
  late final AchievementStore _achievementStore = AchievementStore(
    loadPreferences: widget.testDriver?.achievementPreferencesLoader,
  );
  Future<void> _achievementUpdates = Future<void>.value();
  bool _achievementsLoaded = false;
  bool _achievementsLoadFailed = false;
  bool _achievementsLoading = false;
  Future<void> _progressWrite = Future<void>.value();
  final StageCompletionGate _completionGate = StageCompletionGate();
  bool _completionHandled = false;
  int _lane = 0;
  double _angle = -math.pi / 2;
  double _gemAngle = 0.7;
  int _gemLane = 1;
  final List<_Hazard> _hazards = [];
  double _spawnClock = 0;
  final TemporaryShield _shield = TemporaryShield();
  final math.Random _random = math.Random();
  _ShieldPickup? _shieldPickup;
  double _shieldSpawnClock = 0;
  double _nextShieldSpawnAt = 12;

  StageDefinition get _currentStage => widget.stages[_currentStageIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = widget.audioController ?? GameAudioManager();
    _audio.addListener(_audioSettingsChanged);
    unawaited(
      _audio.initialize().then((_) {
        if (mounted) _audio.setGameState(_audioStateFor(_state));
      }),
    );
    _ticker = createTicker(_tick);
    widget.testDriver?._attach(
      placeShieldAtPlayer: () => setState(() {
        _shieldPickup = _ShieldPickup(_angle, _lane);
      }),
      placeHazardAtPlayer: () => setState(() {
        _hazards.add(_Hazard(_angle, _lane));
      }),
      placeGemAtPlayer: () => setState(() {
        _gemAngle = _angle;
        _gemLane = _lane;
      }),
      moveGemAwayFromPlayer: () => setState(() {
        _gemLane = (_lane + 1) % _currentStage.orbitCount;
        _gemAngle = _angle;
      }),
      readShieldActive: () => _shield.isActive,
      readShieldRemaining: () => _shield.remaining,
      readHazardCount: () => _hazards.length,
      readScore: () => _score,
      readRunState: () => _state,
      readTotalGems: () => _achievementStore.totalGems,
      readAchievementUnlocked: _achievementStore.isUnlocked,
      flushAchievements: _flushAchievements,
    );
    unawaited(_loadAchievements());
    unawaited(_loadStageProgress());
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _best = prefs.getInt('orbit_dash_best') ?? 0);
    });
  }

  Future<void> _loadStageProgress() async {
    final loadedStage = await _stageProgressStore.loadUnlockedStage();
    if (!mounted) return;
    setState(() {
      _highestUnlockedStage = math
          .max(_highestUnlockedStage, loadedStage)
          .toInt();
      _stageProgressLoaded = true;
    });
    if (loadedStage >= 4) {
      _queueAchievementUpdate(
        _achievementStore.unlock(AchievementId.orbitExplorer),
        notify: false,
      );
    }
  }

  Future<void> _loadAchievements() async {
    if (_achievementsLoading || _achievementsLoaded) return;
    _achievementsLoading = true;
    try {
      await _achievementStore.load();
      if (mounted) {
        setState(() {
          _achievementsLoaded = true;
          _achievementsLoadFailed = false;
        });
      }
    } catch (error) {
      debugPrint('Failed to load achievements: $error');
      if (mounted) setState(() => _achievementsLoadFailed = true);
    } finally {
      _achievementsLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _queueAchievementUpdate(
    Future<List<AchievementId>> update, {
    bool notify = true,
  }) {
    _achievementUpdates = _achievementUpdates.then((_) async {
      try {
        final newlyUnlocked = await update;
        if (!mounted) return;
        if (newlyUnlocked.isNotEmpty) setState(() {});
        if (notify) {
          for (final id in newlyUnlocked) {
            _showAchievementNotice(id);
          }
        }
      } catch (error) {
        debugPrint('Failed to update achievements: $error');
      }
    });
  }

  Future<void> _flushAchievements() async {
    await _achievementStore.flush();
    await _achievementUpdates;
  }

  void _showAchievementNotice(AchievementId id) {
    final definition = achievementDefinitions.firstWhere(
      (achievement) => achievement.id == id,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey('achievement-notice-${id.name}'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xff17243a),
          content: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xffffd66e)),
              const SizedBox(width: 10),
              Expanded(child: Text('${definition.title} unlocked!')),
            ],
          ),
        ),
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _audio.setAppActive(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed && _state == RunState.playing) {
      _pause(playEffect: false);
    }
  }

  void _audioSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _tick(Duration now) {
    if (_state != RunState.playing) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : ((now - _lastTick).inMicroseconds / 1000000)
              .clamp(0.0, 0.05)
              .toDouble();
    _lastTick = now;
    setState(() {
      final shieldWasActive = _shield.isActive;
      _shield.advance(Duration(microseconds: (dt * 1000000).round()));
      final speed = playerSpeedForScore(_score);
      _angle += speed * dt;
      _spawnClock += dt;
      if (_spawnClock > hazardSpawnIntervalForScore(_score)) {
        _spawnClock = 0;
        _hazards.add(
          _Hazard(
            (_angle + math.pi + 0.4) % (math.pi * 2),
            hazardLaneForScore(_score, _lane, _currentStage.orbitCount),
          ),
        );
      }
      _updateShieldSpawn(dt);
      final pickup = _shieldPickup;
      if (!shieldWasActive && !_shield.isActive && pickup != null) {
        if (shouldCollectShield(
          playerLane: _lane,
          shieldLane: pickup.lane,
          playerAngle: _angle,
          shieldAngle: pickup.angle,
        )) {
          _shield.activate();
          _shieldPickup = null;
          _shieldSpawnClock = 0;
        }
      }
      final absorbedHazards = <_Hazard>[];
      for (final hazard in _hazards) {
        hazard.angle = (hazard.angle + speed * 0.7 * dt) % (math.pi * 2);
        final collision = isLaneCollision(
          playerLane: _lane,
          hazardLane: hazard.lane,
          playerAngle: _angle,
          hazardAngle: hazard.angle,
        );
        final collisionResponse = shieldCollisionResponse(
          _shield,
          collision: collision,
        );
        if (collisionResponse != ShieldCollisionResponse.noCollision) {
          if (collisionResponse == ShieldCollisionResponse.absorbed) {
            absorbedHazards.add(hazard);
            _queueAchievementUpdate(
              _achievementStore.unlock(AchievementId.savedByShield),
            );
            continue;
          }
          _finish();
          return;
        }
        hazard.relativeAngleTravel += speed * 0.3 * dt;
      }
      _hazards.removeWhere(
        (h) =>
            absorbedHazards.contains(h) ||
            hazardLifetimeExpired(h.relativeAngleTravel),
      );
      if (shouldCollectGem(
        playerLane: _lane,
        gemLane: _gemLane,
        playerAngle: _angle,
        gemAngle: _gemAngle,
      )) {
        _score++;
        _audio.playEffect(GameSoundEffect.gemCollect);
        _gemAngle = (_angle + 2.4 + (_score % 3) * 0.45) % (math.pi * 2);
        _gemLane = nextOrbitLane(_gemLane, _currentStage.orbitCount);
        _queueAchievementUpdate(_achievementStore.recordGem());
        if (_completionGate.completeIfReached(_score, _currentStage)) {
          _completeStage();
          return;
        }
      }
    });
  }

  void _updateShieldSpawn(double dt) {
    if (_shield.isActive || _shieldPickup != null) {
      _shieldSpawnClock = 0;
      return;
    }
    _shieldSpawnClock += dt;
    if (_shieldSpawnClock < _nextShieldSpawnAt) return;

    _shieldSpawnClock = 0;
    _nextShieldSpawnAt = 12 + _random.nextDouble() * 8;
    _shieldPickup = _ShieldPickup(
      (_angle + 0.4 + _random.nextDouble() * 1.4) % _fullTurn,
      _random.nextInt(_currentStage.orbitCount),
    );
  }

  void _start({int? stageIndex}) {
    final requestedStage = stageIndex ?? _currentStageIndex;
    if (requestedStage < 0 ||
        requestedStage >= widget.stages.length ||
        requestedStage + 1 > _highestUnlockedStage) {
      return;
    }
    setState(() {
      _currentStageIndex = requestedStage;
      _score = 0;
      _lane = 0;
      _angle = -math.pi / 2;
      _spawnClock = 0;
      _hazards.clear();
      _shield.reset();
      _shieldPickup = null;
      _shieldSpawnClock = 0;
      _nextShieldSpawnAt = 12 + _random.nextDouble() * 8;
      _gemAngle = 0.7;
      _gemLane = nextOrbitLane(0, _currentStage.orbitCount);
      _completionGate.reset();
      _completionHandled = false;
      _state = RunState.playing;
      _lastTick = Duration.zero;
    });
    _ticker.start();
    _audio.setGameState(AudioRunState.playing);
    _audio.playEffect(GameSoundEffect.start);
  }

  void _finish() {
    if (_state != RunState.playing) return;
    _state = RunState.over;
    _ticker.stop();
    _shield.reset();
    _shieldPickup = null;
    _audio.setGameState(AudioRunState.over);
    _audio.playEffect(GameSoundEffect.collision);
    _saveBestScore();
  }

  void _completeStage() {
    if (_state != RunState.playing || _completionHandled) return;
    _completionHandled = true;
    _shield.reset();
    _shieldPickup = null;
    _state = _currentStageIndex == widget.stages.length - 1
        ? RunState.gameComplete
        : RunState.stageComplete;
    _ticker.stop();
    _audio.setGameState(AudioRunState.over);
    _saveBestScore();
    final nextStage = _currentStageIndex + 1 < widget.stages.length
        ? widget.stages[_currentStageIndex + 1].number
        : null;
    if (nextStage != null && nextStage > _highestUnlockedStage) {
      _highestUnlockedStage = nextStage;
      _progressWrite = _progressWrite.then(
        (_) => _stageProgressStore.unlockThrough(_highestUnlockedStage),
      );
      _progressWrite = _progressWrite.catchError((Object error) {
        debugPrint('Failed to save stage progress: $error');
      });
      unawaited(_progressWrite);
      if (nextStage == 4) {
        _queueAchievementUpdate(
          _achievementStore.unlock(AchievementId.orbitExplorer),
        );
      }
    }
    if (_currentStage.number == 5 && _state == RunState.gameComplete) {
      _queueAchievementUpdate(
        _achievementStore.unlock(AchievementId.orbitalMaster),
      );
    }
  }

  void _saveBestScore() {
    if (_score <= _best) return;
    _best = _score;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt('orbit_dash_best', _best),
      ),
    );
  }

  Future<void> _continueToNextStage() async {
    if (_state != RunState.stageComplete ||
        _currentStageIndex >= widget.stages.length - 1) {
      return;
    }
    await _progressWrite;
    if (!mounted) return;
    _start(stageIndex: _currentStageIndex + 1);
  }

  Future<void> _selectStage(int stageIndex) async {
    if (stageIndex < 0 ||
        stageIndex >= widget.stages.length ||
        stageIndex + 1 > _highestUnlockedStage ||
        (!_stageProgressLoaded && stageIndex > 0)) {
      return;
    }
    await _progressWrite;
    if (!mounted) return;
    _start(stageIndex: stageIndex);
  }

  void _pause({bool playEffect = true}) {
    setState(() => _state = RunState.paused);
    _ticker.stop();
    _audio.setGameState(AudioRunState.paused);
    if (playEffect) _audio.playEffect(GameSoundEffect.pause);
  }

  void _resume() {
    setState(() => _state = RunState.playing);
    _lastTick = Duration.zero;
    _ticker.start();
    _audio.setGameState(AudioRunState.playing);
    _audio.playEffect(GameSoundEffect.resume);
  }

  void _returnToMenu() {
    _ticker.stop();
    _hazards.clear();
    _spawnClock = 0;
    _shield.reset();
    _shieldPickup = null;
    _shieldSpawnClock = 0;
    _lastTick = Duration.zero;
    setState(() => _state = RunState.ready);
    _audio.setGameState(AudioRunState.menu);
  }

  void _openStageSelection() {
    setState(() => _state = RunState.selectingStage);
    _audio.setGameState(AudioRunState.menu);
  }

  void _openAchievements() {
    setState(() => _state = RunState.achievements);
    _audio.setGameState(AudioRunState.menu);
  }

  void _tapGame(Offset globalPosition) {
    if (_state == RunState.playing) {
      final canvas =
          _orbitCanvasKey.currentContext!.findRenderObject()! as RenderBox;
      final selectedLane = laneAfterOrbitTouch(
        _lane,
        OrbitGeometry.forSizeAndCount(
          canvas.size,
          orbitCount: _currentStage.orbitCount,
        ),
        canvas.globalToLocal(globalPosition),
      );
      if (selectedLane == _lane) return;
      setState(() => _lane = selectedLane);
      _audio.playEffect(GameSoundEffect.orbitSwitch);
    }
  }

  AudioRunState _audioStateFor(RunState state) => switch (state) {
    // The ready overlay is the app's actual start/menu screen.
    RunState.ready ||
    RunState.selectingStage ||
    RunState.achievements => AudioRunState.menu,
    RunState.playing => AudioRunState.playing,
    RunState.paused => AudioRunState.paused,
    RunState.over ||
    RunState.stageComplete ||
    RunState.gameComplete => AudioRunState.over,
  };

  void _toggleMusic() {
    unawaited(_audio.setMusicEnabled(!_audio.musicEnabled));
  }

  void _toggleEffects() {
    unawaited(_audio.setEffectsEnabled(!_audio.effectsEnabled));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _audio.removeListener(_audioSettingsChanged);
    unawaited(_audio.shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth = constraints.maxWidth < 400;
          final side = math.min(
            constraints.maxWidth,
            constraints.maxHeight * 0.87,
          );
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compactWidth ? 12 : 24,
                  14,
                  compactWidth ? 12 : 24,
                  4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.blur_circular,
                      color: Color(0xff5ae8ff),
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    if (!compactWidth)
                      const Text(
                        'ORBIT DASH',
                        style: TextStyle(
                          letterSpacing: 3,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    const Spacer(),
                    if (_state == RunState.ready)
                      IconButton(
                        onPressed: _openAchievements,
                        tooltip: 'Achievements',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.emoji_events_rounded,
                          color: Color(0xffffd66e),
                        ),
                      ),
                    if (_state != RunState.playing &&
                        constraints.maxWidth >= 400) ...[
                      IconButton(
                        onPressed: _toggleMusic,
                        tooltip: _audio.musicEnabled ? 'Music on' : 'Music off',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _audio.musicEnabled
                              ? Icons.music_note_rounded
                              : Icons.music_off_rounded,
                          color: _audio.musicEnabled
                              ? const Color(0xff65eaff)
                              : Colors.white38,
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleEffects,
                        tooltip: _audio.effectsEnabled
                            ? 'Sound effects on'
                            : 'Sound effects off',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _audio.effectsEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          color: _audio.effectsEnabled
                              ? const Color(0xff65eaff)
                              : Colors.white38,
                        ),
                      ),
                    ],
                    if (_state == RunState.playing) ...[
                      _scorePill('BEST', '$_best'),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _pause,
                        tooltip: 'Pause',
                        icon: const Icon(
                          Icons.pause_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('game-area'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _tapGame(details.globalPosition),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        key: _orbitCanvasKey,
                        width: side,
                        height: side,
                        child: KeyedSubtree(
                          key: ValueKey('orbit-lane-$_lane'),
                          child: CustomPaint(
                            key: _shield.isActive
                                ? const ValueKey('shield-aura-visible')
                                : null,
                            size: Size.square(side),
                            painter: _OrbitPainter(
                              angle: _angle,
                              lane: _lane,
                              orbitCount: _currentStage.orbitCount,
                              hazards: List.of(_hazards),
                              gemAngle: _gemAngle,
                              gemLane: _gemLane,
                              shieldAngle: _shieldPickup?.angle,
                              shieldLane: _shieldPickup?.lane,
                              shieldActive: _shield.isActive,
                            ),
                          ),
                        ),
                      ),
                      if (_state == RunState.playing)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'STAGE ${_currentStage.number} · $_score/${_currentStage.targetScore}',
                                  key: const ValueKey('current-stage'),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    letterSpacing: 1.2,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$_score',
                                  key: const ValueKey('score'),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.white,
                                    height: 1.12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_state != RunState.playing) _overlay(),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: Color(0xff7d8ba5),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'TAP AN ORBIT TO MOVE',
                      style: TextStyle(
                        color: Color(0xff7d8ba5),
                        letterSpacing: 2,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _scorePill(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xff141b2e),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        Text(
          '$label  ',
          style: const TextStyle(
            color: Color(0xff71809d),
            fontSize: 9,
            letterSpacing: 1.4,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  Widget _overlay() {
    final ready = _state == RunState.ready;
    final paused = _state == RunState.paused;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final horizontalPadding = constraints.maxWidth < 330 ? 20.0 : 24.0;
        final cardWidth = math.min(340.0, constraints.maxWidth - 28);
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: cardWidth,
              maxHeight: constraints.maxHeight - 24,
            ),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: compact ? 20 : 26,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xed0d1427),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0x554fe7ff),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2600cfff), blurRadius: 24),
                  ],
                ),
                child: _overlayContent(
                  ready: ready,
                  paused: paused,
                  compact: compact,
                  showAudioControls: constraints.maxWidth < 400,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _overlayContent({
    required bool ready,
    required bool paused,
    required bool compact,
    required bool showAudioControls,
  }) {
    if (_state == RunState.selectingStage) {
      return _stageSelectionContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }
    if (_state == RunState.achievements) {
      return _achievementContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }

    final stage = _currentStage;
    final lost = _state == RunState.over;
    final stageComplete = _state == RunState.stageComplete;
    final gameComplete = _state == RunState.gameComplete;
    final completed = stageComplete || gameComplete;
    final spacing = compact ? 10.0 : 14.0;
    final title = ready
        ? 'READY, PILOT?'
        : paused
        ? 'PAUSED'
        : lost
        ? 'STAGE FAILED'
        : stageComplete
        ? 'STAGE COMPLETE'
        : 'GAME COMPLETE';
    final subtitle = ready
        ? 'Dodge the red. Chase the glow.'
        : paused
        ? 'Your orbit is on hold.'
        : lost
        ? 'You collected $_score ${_score == 1 ? 'shard' : 'shards'}.'
        : stageComplete
        ? '${stage.name} complete. Next: ${widget.stages[_currentStageIndex + 1].name}.'
        : 'You mastered all five stages.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready
              ? Icons.auto_awesome_rounded
              : paused
              ? Icons.pause_circle_outline_rounded
              : completed
              ? Icons.emoji_events_rounded
              : Icons.sports_score_rounded,
          color: completed
              ? const Color(0xffffd66e)
              : paused
              ? const Color(0xff65eaff)
              : ready
              ? const Color(0xff52e5ff)
              : const Color(0xffff7180),
          size: compact ? 30 : 36,
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 16 : 18,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 5 : 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xffaebbd2),
            fontSize: 12,
            height: 1.45,
          ),
        ),
        if (ready) ...[
          SizedBox(height: spacing),
          Text(
            'STAGE ${stage.number} · ${stage.name.toUpperCase()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xffd2deef),
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'TARGET ${stage.targetScore}  ·  ${stage.orbitCount} ORBITS',
            style: const TextStyle(
              color: Color(0xff8c9bb5),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          _resultCard(label: 'BEST FLIGHT', value: '$_best'),
        ],
        if (paused) ...[
          SizedBox(height: spacing),
          _resultCard(label: 'CURRENT SCORE', value: '$_score'),
          const SizedBox(height: 6),
          Text(
            'STAGE ${stage.number} · ${stage.name}',
            style: const TextStyle(color: Color(0xff8c9bb5), fontSize: 10),
          ),
        ],
        if (lost || completed) ...[
          SizedBox(height: compact ? 8 : 12),
          Text(
            lost ? 'FINAL SCORE' : 'STAGE SCORE',
            style: const TextStyle(
              color: Color(0xff8c9bb5),
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$_score',
            style: TextStyle(
              color: const Color(0xff61e9ff),
              fontSize: compact ? 50 : 58,
              height: 1.08,
              fontWeight: FontWeight.w300,
            ),
          ),
          if (stageComplete)
            Text(
              'NEXT STAGE UNLOCKED',
              style: const TextStyle(
                color: Color(0xff65eaff),
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          SizedBox(height: compact ? 6 : 10),
          _resultCard(label: 'BEST FLIGHT', value: '$_best'),
        ],
        if (showAudioControls) ...[
          SizedBox(height: compact ? 8 : 12),
          _audioSettingsRow(),
        ],
        SizedBox(height: compact ? 12 : 18),
        _primaryButton(
          label: ready
              ? 'START RUN'
              : paused
              ? 'RESUME'
              : lost
              ? 'RETRY STAGE'
              : stageComplete
              ? 'CONTINUE TO STAGE ${stage.number + 1}'
              : 'PLAY AGAIN',
          onPressed: ready
              ? _start
              : paused
              ? _resume
              : lost
              ? _start
              : stageComplete
              ? () => unawaited(_continueToNextStage())
              : () => _start(stageIndex: 0),
        ),
        if (ready || paused || lost || completed) ...[
          const SizedBox(height: 8),
          _secondaryButton(
            label: ready
                ? 'SELECT STAGE'
                : paused
                ? 'RESTART STAGE'
                : 'MAIN MENU',
            icon: ready
                ? Icons.view_carousel_rounded
                : paused
                ? Icons.replay_rounded
                : Icons.home_rounded,
            onPressed: ready
                ? _openStageSelection
                : paused
                ? _start
                : _returnToMenu,
          ),
        ],
        if (paused) ...[
          const SizedBox(height: 8),
          _secondaryButton(
            label: 'MAIN MENU',
            icon: Icons.home_rounded,
            onPressed: _returnToMenu,
          ),
        ],
      ],
    );
  }

  Widget _achievementContent({
    required bool compact,
    required bool showAudioControls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.emoji_events_rounded,
        color: const Color(0xffffd66e),
        size: compact ? 30 : 36,
      ),
      SizedBox(height: compact ? 7 : 10),
      Text(
        'ACHIEVEMENTS',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 16 : 18,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      if (_achievementsLoaded) ...[
        Text(
          'Total gems: ${_achievementStore.totalGems}',
          style: const TextStyle(color: Color(0xffaebbd2), fontSize: 12),
        ),
        SizedBox(height: compact ? 9 : 13),
        for (final achievement in achievementDefinitions)
          _achievementRow(achievement),
      ] else if (_achievementsLoadFailed) ...[
        const SizedBox(height: 7),
        const Text(
          'Could not load saved achievements. Your saved progress is unchanged.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xffffb4a9), fontSize: 12),
        ),
        SizedBox(height: compact ? 9 : 13),
        _secondaryButton(
          label: 'RETRY',
          icon: Icons.refresh_rounded,
          onPressed: () => unawaited(_loadAchievements()),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Loading saved progress…',
            style: TextStyle(color: Color(0xffaebbd2), fontSize: 12),
          ),
        ),
      if (showAudioControls) ...[
        SizedBox(height: compact ? 5 : 8),
        _audioSettingsRow(),
      ],
      SizedBox(height: compact ? 8 : 12),
      _secondaryButton(
        label: 'MAIN MENU',
        icon: Icons.home_rounded,
        onPressed: _returnToMenu,
      ),
    ],
  );

  Widget _achievementRow(AchievementDefinition achievement) {
    final unlocked = _achievementStore.isUnlocked(achievement.id);
    final progress = switch (achievement.id) {
      AchievementId.firstSteps || AchievementId.gemCollector =>
        '${math.min(_achievementStore.totalGems, achievement.gemGoal!)}/${achievement.gemGoal} gems',
      AchievementId.savedByShield =>
        unlocked ? 'Shield absorbed a collision' : 'No collision absorbed yet',
      AchievementId.orbitExplorer =>
        '${math.min(_highestUnlockedStage, 4)}/4 stages unlocked',
      AchievementId.orbitalMaster =>
        unlocked ? 'Final stage completed' : 'Stage 5 not completed yet',
    };
    return Container(
      key: ValueKey('achievement-${achievement.id.name}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xff151e33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked ? const Color(0x6670e9ff) : const Color(0x337d8ba5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.workspace_premium_rounded : Icons.lock_outline,
            color: unlocked ? const Color(0xffffd66e) : Colors.white38,
            size: 22,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff9baac3),
                    fontSize: 9,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  progress,
                  style: const TextStyle(
                    color: Color(0xff65eaff),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            unlocked ? 'OPEN' : 'LOCKED',
            key: ValueKey('achievement-status-${achievement.id.name}'),
            style: TextStyle(
              color: unlocked ? const Color(0xffffd66e) : Colors.white38,
              fontSize: 8,
              letterSpacing: .7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageSelectionContent({
    required bool compact,
    required bool showAudioControls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.view_carousel_rounded,
        color: const Color(0xff65eaff),
        size: compact ? 30 : 36,
      ),
      SizedBox(height: compact ? 8 : 12),
      Text(
        'SELECT STAGE',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 16 : 18,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Choose any stage you have unlocked.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xffaebbd2), fontSize: 12),
      ),
      SizedBox(height: compact ? 10 : 14),
      for (final stage in widget.stages) _stageOption(stage, compact: compact),
      if (showAudioControls) ...[
        SizedBox(height: compact ? 6 : 10),
        _audioSettingsRow(),
      ],
      SizedBox(height: compact ? 8 : 12),
      _secondaryButton(
        label: 'MAIN MENU',
        icon: Icons.home_rounded,
        onPressed: _returnToMenu,
      ),
    ],
  );

  Widget _stageOption(StageDefinition stage, {required bool compact}) {
    final open = stage.number <= _highestUnlockedStage;
    final enabled = open && (_stageProgressLoaded || stage.number == 1);
    final buttonHeight = compact ? 54.0 : 60.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: OutlinedButton(
          key: ValueKey('stage-option-${stage.number}'),
          onPressed: enabled
              ? () => unawaited(_selectStage(stage.number - 1))
              : null,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            side: BorderSide(
              color: open ? const Color(0x6670e9ff) : const Color(0x337d8ba5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Icon(
                open ? Icons.play_circle_outline_rounded : Icons.lock_outline,
                color: open ? const Color(0xff65eaff) : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stage.number}. ${stage.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${stage.targetScore} points · ${stage.orbitCount} orbits',
                      style: const TextStyle(
                        color: Color(0xff9baac3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                open ? 'OPEN' : 'LOCKED',
                style: TextStyle(
                  color: open ? const Color(0xff65eaff) : Colors.white38,
                  fontSize: 9,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _audioSettingsRow() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        onPressed: _toggleMusic,
        tooltip: _audio.musicEnabled ? 'Music on' : 'Music off',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          _audio.musicEnabled
              ? Icons.music_note_rounded
              : Icons.music_off_rounded,
          color: _audio.musicEnabled ? const Color(0xff65eaff) : Colors.white38,
        ),
      ),
      IconButton(
        onPressed: _toggleEffects,
        tooltip: _audio.effectsEnabled
            ? 'Sound effects on'
            : 'Sound effects off',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          _audio.effectsEnabled
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          color: _audio.effectsEnabled
              ? const Color(0xff65eaff)
              : Colors.white38,
        ),
      ),
    ],
  );

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    height: 56,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff54e6ff),
        foregroundColor: const Color(0xff06101d),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 23),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          letterSpacing: 1.3,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    height: 48,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xffc3d0e6),
        side: const BorderSide(color: Color(0x557d8ba5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      icon: Icon(icon, size: 19),
      label: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    ),
  );
  Widget _resultCard({required String label, required String value}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xff151e33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x334fe7ff)),
        ),
        child: Row(
          children: [
            const Icon(Icons.stars_rounded, color: Color(0xffffd66e), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xff9baac3),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _Hazard {
  _Hazard(this.angle, this.lane);
  double angle;
  final int lane;
  double relativeAngleTravel = 0;
}

class _ShieldPickup {
  const _ShieldPickup(this.angle, this.lane);

  final double angle;
  final int lane;
}

class _Star {
  const _Star(this.x, this.y, this.radius, this.paint);

  final double x;
  final double y;
  final double radius;
  final Paint paint;
}

class _OrbitPainter extends CustomPainter {
  static final List<_Star> _stars = List<_Star>.generate(70, (i) {
    final x = (math.sin(i * 127.1) * 43758.5).abs() % 1;
    final y = (math.sin(i * 71.7 + 2) * 11923.4).abs() % 1;
    final alpha = .12 + (i % 5) * .025;
    return _Star(
      x,
      y,
      i % 9 == 0 ? 1.2 : .65,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  });

  const _OrbitPainter({
    required this.angle,
    required this.lane,
    required this.orbitCount,
    required this.hazards,
    required this.gemAngle,
    required this.gemLane,
    required this.shieldAngle,
    required this.shieldLane,
    required this.shieldActive,
  });
  final double angle, gemAngle;
  final int lane, gemLane, orbitCount;
  final List<_Hazard> hazards;
  final double? shieldAngle;
  final int? shieldLane;
  final bool shieldActive;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = OrbitGeometry.forSizeAndCount(
      size,
      orbitCount: orbitCount,
    );
    final center = geometry.center;
    final radius = geometry.outerRadius;
    final bg = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xff111b37).withValues(alpha: .75),
          const Color(0xff070b18).withValues(alpha: 0),
        ],
        stops: const [0, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.7));
    canvas.drawCircle(center, radius * 1.7, bg);
    for (final star in _stars) {
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        star.paint,
      );
    }
    for (final r in geometry.radii) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = const Color(0xff50dff8).withValues(alpha: .055)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = const Color(0xff75dcf5).withValues(alpha: .64)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .55,
      );
    }
    _orbitMarkers(canvas, center, geometry.radii);
    _planet(canvas, center, radius * (orbitCount == 2 ? .40 : .10));
    if (shieldActive) {
      _shieldAura(canvas, center, geometry.radiusForLane(lane), angle);
    }
    _orbitalThing(
      canvas,
      center,
      geometry.radiusForLane(lane),
      angle,
      const Color(0xff60efff),
      8,
      glow: true,
      trail: true,
    );
    for (final hazard in hazards) {
      _orbitalThing(
        canvas,
        center,
        geometry.radiusForLane(hazard.lane),
        hazard.angle,
        const Color(0xffff445d),
        9,
        glow: true,
      );
    }
    _gem(canvas, center, geometry.radiusForLane(gemLane), gemAngle);
    if (shieldAngle != null && shieldLane != null) {
      _shieldPickup(
        canvas,
        center,
        geometry.radiusForLane(shieldLane!),
        shieldAngle!,
      );
    }
  }

  void _shieldAura(Canvas canvas, Offset center, double radius, double a) {
    final player = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
    canvas.drawCircle(
      player,
      15,
      Paint()
        ..color = const Color(0xff45eaff).withValues(alpha: .46)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      player,
      19,
      Paint()
        ..color = const Color(0xff8c77ff).withValues(alpha: .32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _shieldPickup(Canvas canvas, Offset center, double radius, double a) {
    final p = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
    canvas.drawCircle(
      p,
      14,
      Paint()..color = const Color(0xff53edff).withValues(alpha: .2),
    );
    final shieldPath = Path()
      ..moveTo(p.dx, p.dy - 9)
      ..lineTo(p.dx + 7, p.dy - 6)
      ..lineTo(p.dx + 6, p.dy + 2)
      ..quadraticBezierTo(p.dx + 4, p.dy + 7, p.dx, p.dy + 9)
      ..quadraticBezierTo(p.dx - 4, p.dy + 7, p.dx - 6, p.dy + 2)
      ..lineTo(p.dx - 7, p.dy - 6)
      ..close();
    canvas.drawPath(
      shieldPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffc5fbff), Color(0xff31aaff), Color(0xff715cff)],
        ).createShader(Rect.fromCenter(center: p, width: 16, height: 20)),
    );
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = const Color(0xffe7ffff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _orbitMarkers(Canvas canvas, Offset center, List<double> radii) {
    final paint = Paint()
      ..color = const Color(0xff8cecff).withValues(alpha: .35)
      ..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final angle = i * _fullTurn / 12;
      if (radii.length == 2) {
        _radialMark(
          canvas,
          center,
          radii.first - 2,
          i % 3 == 0 ? radii.last + 5 : radii.first + 2,
          angle,
          paint,
        );
      } else if (i % 3 == 0) {
        _radialMark(
          canvas,
          center,
          radii.first - 2,
          radii.last + 5,
          angle,
          paint,
        );
      } else {
        for (final radius in radii) {
          _radialMark(canvas, center, radius - 2, radius + 2, angle, paint);
        }
      }
    }
  }

  void _radialMark(
    Canvas canvas,
    Offset center,
    double startRadius,
    double endRadius,
    double angle,
    Paint paint,
  ) {
    canvas.drawLine(
      center +
          Offset(math.cos(angle) * startRadius, math.sin(angle) * startRadius),
      center + Offset(math.cos(angle) * endRadius, math.sin(angle) * endRadius),
      paint,
    );
  }

  void _planet(Canvas c, Offset center, double r) {
    c.drawCircle(
      center,
      r * 1.25,
      Paint()..color = const Color(0xff455cff).withValues(alpha: .11),
    );
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.5),
          colors: [
            Color(0xffd8a0ff),
            Color(0xff5f56bb),
            Color(0xff201d54),
            Color(0xff10152f),
          ],
          stops: [0, .35, .78, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    final clip = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    c.save();
    c.clipPath(clip);
    for (int i = 0; i < 4; i++) {
      final y = center.dy + (i - 1.5) * r * .42;
      final band = Path()
        ..moveTo(center.dx - r, y)
        ..quadraticBezierTo(
          center.dx - r * .15,
          y - r * .18,
          center.dx + r,
          y + r * .04,
        );
      c.drawPath(
        band,
        Paint()
          ..color = const Color(0xffd9bdff).withValues(alpha: .13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = i.isEven ? r * .09 : r * .045,
      );
    }
    // Small, clipped craters add surface detail without blur filters.
    for (final crater in [
      Offset(-.34, -.12),
      Offset(.28, .18),
      Offset(-.08, .48),
    ]) {
      final craterCenter = center + Offset(crater.dx * r, crater.dy * r);
      c.drawCircle(
        craterCenter,
        r * .095,
        Paint()..color = const Color(0xff17183e).withValues(alpha: .28),
      );
      c.drawArc(
        Rect.fromCircle(center: craterCenter, radius: r * .095),
        math.pi * 1.1,
        math.pi * .9,
        false,
        Paint()
          ..color = const Color(0xffe4caff).withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65,
      );
    }
    c.restore();
    c.drawArc(
      Rect.fromCircle(center: center, radius: r - .8),
      math.pi * 1.08,
      math.pi * .72,
      false,
      Paint()
        ..color = const Color(0xfff0d5ff).withValues(alpha: .48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    c.drawCircle(
      center,
      r,
      Paint()
        ..color = const Color(0xffa9a0ff).withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _orbitalThing(
    Canvas c,
    Offset center,
    double r,
    double a,
    Color color,
    double dot, {
    bool glow = false,
    bool trail = false,
  }) {
    final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
    if (trail) {
      for (int i = 3; i >= 1; i--) {
        final trailAngle = a - i * .055;
        final trailPoint =
            center + Offset(math.cos(trailAngle) * r, math.sin(trailAngle) * r);
        c.drawCircle(
          trailPoint,
          dot * (1 - i * .16),
          Paint()
            ..color = const Color(0xff60efff)
                .withValues(alpha: .10 + .06 * (3 - i)),
        );
      }
    }
    if (glow) {
      c.drawCircle(
        p,
        dot * 1.65,
        Paint()..color = color.withValues(alpha: .16),
      );
    }
    if (color == const Color(0xffff445d)) {
      c.drawCircle(
        p,
        dot + 1.5,
        Paint()
          ..color = const Color(0xffffb0b8).withValues(alpha: .72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    c.drawCircle(p, dot, Paint()..color = color);
    c.drawCircle(
      p,
      dot * .48,
      Paint()..color = Colors.white.withValues(alpha: .9),
    );
  }

  void _gem(Canvas c, Offset center, double r, double a) {
    final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
    final color = const Color(0xffffd66e);
    final pulse = .5 + .5 * math.sin(angle * 5);
    final glowRadius = 10 + pulse * 2;
    c.drawCircle(
      p,
      glowRadius,
      Paint()..color = color.withValues(alpha: .12 + pulse * .10),
    );
    final path = Path()
      ..moveTo(p.dx, p.dy - 8)
      ..lineTo(p.dx + 6, p.dy)
      ..lineTo(p.dx, p.dy + 8)
      ..lineTo(p.dx - 6, p.dy)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffffffc0), Color(0xffffa82e)],
        ).createShader(Rect.fromCenter(center: p, width: 14, height: 18)),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => true;
}
