import 'dart:async';
import 'dart:math' as math;

import 'package:orbit_dash/achievements.dart';
import 'package:orbit_dash/audio/game_audio_manager.dart';
import 'package:orbit_dash/daily_challenges.dart';
import 'package:orbit_dash/gem_wallet.dart';
import 'package:orbit_dash/player_statistics.dart';
import 'package:orbit_dash/skins.dart';
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
  playing,
  paused,
  over,
  achievements,
  skins,
  statistics,
  dailyChallenges,
}

enum CosmeticShopCategory { ship, orbit, core, trail }

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
  late int Function() _readOrbitCount;
  late RunState Function() _readRunState;
  late int Function() _readTotalGems;
  late int Function() _readWalletBalance;
  late bool Function(AchievementId id) _readAchievementUnlocked;
  late Future<void> Function() _flushAchievements;
  late int Function() _readRunsStarted;
  late int Function() _readShieldAbsorptions;
  late int Function() _readLosses;
  late ShipSkinId Function() _readSelectedSkin;
  late OrbitSkinId Function() _readSelectedOrbit;
  late CoreSkinId Function() _readSelectedCore;
  late TrailSkinId Function() _readSelectedTrail;
  late bool Function(ShipSkinId id) _readSkinUnlocked;
  late Future<void> Function() _flushProgress;
  late void Function(Future<void> Function()) _enqueueFeatureWrite;

  bool get shieldActive => _readShieldActive();
  Duration get shieldRemaining => _readShieldRemaining();
  int get hazardCount => _readHazardCount();
  int get score => _readScore();
  int get orbitCount => _readOrbitCount();
  RunState get runState => _readRunState();
  int get totalGems => _readTotalGems();
  int get walletBalance => _readWalletBalance();
  bool achievementUnlocked(AchievementId id) => _readAchievementUnlocked(id);
  Future<void> flushAchievements() => _flushAchievements();
  int get runsStarted => _readRunsStarted();
  int get shieldAbsorptions => _readShieldAbsorptions();
  int get losses => _readLosses();
  ShipSkinId get selectedSkin => _readSelectedSkin();
  OrbitSkinId get selectedOrbit => _readSelectedOrbit();
  CoreSkinId get selectedCore => _readSelectedCore();
  TrailSkinId get selectedTrail => _readSelectedTrail();
  bool skinUnlocked(ShipSkinId id) => _readSkinUnlocked(id);
  Future<void> flushProgress() => _flushProgress();
  void queueFeatureWrite(Future<void> Function() write) =>
      _enqueueFeatureWrite(write);

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
    required int Function() readOrbitCount,
    required RunState Function() readRunState,
    required int Function() readTotalGems,
    required int Function() readWalletBalance,
    required bool Function(AchievementId id) readAchievementUnlocked,
    required Future<void> Function() flushAchievements,
    required int Function() readRunsStarted,
    required int Function() readShieldAbsorptions,
    required int Function() readLosses,
    required ShipSkinId Function() readSelectedSkin,
    required OrbitSkinId Function() readSelectedOrbit,
    required CoreSkinId Function() readSelectedCore,
    required TrailSkinId Function() readSelectedTrail,
    required bool Function(ShipSkinId id) readSkinUnlocked,
    required Future<void> Function() flushProgress,
    required void Function(Future<void> Function()) enqueueFeatureWrite,
  }) {
    _placeShieldAtPlayer = placeShieldAtPlayer;
    _placeHazardAtPlayer = placeHazardAtPlayer;
    _placeGemAtPlayer = placeGemAtPlayer;
    _moveGemAwayFromPlayer = moveGemAwayFromPlayer;
    _readShieldActive = readShieldActive;
    _readShieldRemaining = readShieldRemaining;
    _readHazardCount = readHazardCount;
    _readScore = readScore;
    _readOrbitCount = readOrbitCount;
    _readRunState = readRunState;
    _readTotalGems = readTotalGems;
    _readWalletBalance = readWalletBalance;
    _readAchievementUnlocked = readAchievementUnlocked;
    _flushAchievements = flushAchievements;
    _readRunsStarted = readRunsStarted;
    _readShieldAbsorptions = readShieldAbsorptions;
    _readLosses = readLosses;
    _readSelectedSkin = readSelectedSkin;
    _readSelectedOrbit = readSelectedOrbit;
    _readSelectedCore = readSelectedCore;
    _readSelectedTrail = readSelectedTrail;
    _readSkinUnlocked = readSkinUnlocked;
    _flushProgress = flushProgress;
    _enqueueFeatureWrite = enqueueFeatureWrite;
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
    return OrbitGeometry(
      center: Offset(size.width / 2, size.height / 2 + size.height * 0.035),
      radii: List<double>.unmodifiable(
        [
          0.245,
          0.34,
          0.385,
          0.43,
          0.475,
        ].take(orbitCount).map((fraction) => size.width * fraction).toList(),
      ),
    );
  }

  final Offset center;
  final List<double> radii;
  double get innerRadius => radii.first;
  double get outerRadius => radii.last;
  double get touchTolerance {
    var minimumGap = double.infinity;
    for (var lane = 1; lane < radii.length; lane++) {
      minimumGap = math.min(minimumGap, radii[lane] - radii[lane - 1]);
    }
    return math.min(18.0, minimumGap / 2);
  }

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

const double maxSurvivalPlayerSpeed = 2.75;
const double minSurvivalHazardInterval = 0.95;
double playerSpeedForScore(int score) =>
    1.55 +
    math.min(
      1.2 * (1 - math.exp(-math.max(0, score) / 120)),
      maxSurvivalPlayerSpeed - 1.55,
    );

double hazardSpawnIntervalForScore(int score) =>
    math.max(minSurvivalHazardInterval, 2.0 - math.max(0, score) * 0.0035);

const List<int> survivalOrbitThresholds = [10, 25, 45];
int survivalOrbitCountForScore(int score) =>
    2 + survivalOrbitThresholds.where((threshold) => score >= threshold).length;

({int lane, double angle}) randomizedGemPlacement({
  required int orbitCount,
  required math.Random random,
  double? avoidAngle,
}) {
  final lane = random.nextInt(orbitCount);
  var angle = random.nextDouble() * _fullTurn;
  if (avoidAngle != null && shortestAngularDistance(angle, avoidAngle) < 0.65) {
    angle = (angle + math.pi) % _fullTurn;
  }
  return (lane: lane, angle: angle);
}

class OrbitGamePage extends StatefulWidget {
  const OrbitGamePage({
    super.key,
    this.audioController,
    this.testDriver,
    this.dailyChallengesNow,
  });

  final GameAudioController? audioController;
  final OrbitGameTestDriver? testDriver;
  final DateTime Function()? dailyChallengesNow;

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
  int _orbitCount = 2;
  int _highestOrbitCount = 2;
  bool _newRecord = false;
  static const _survivalBestKey = 'orbit_dash_survival_best';
  final PlayerStatisticsStore _statisticsStore = PlayerStatisticsStore();
  final SkinStore _skinStore = SkinStore();
  final AppearanceStore _appearanceStore = AppearanceStore();
  final GemWallet _wallet = GemWallet();
  int _pickupSequence = 0;
  int _runToken = 0;
  bool _purchaseInProgress = false;
  CosmeticShopCategory _selectedShopCategory = CosmeticShopCategory.ship;
  late final DailyChallengeStore _dailyChallengeStore;
  bool _dailyChallengesLoaded = false;
  bool _dailyChallengesLoadFailed = false;
  bool _featureStoresLoaded = false;
  bool _featureStoreLoadFailed = false;
  late Future<void> _featureStoresReady;
  late final AchievementStore _achievementStore = AchievementStore(
    loadPreferences: widget.testDriver?.achievementPreferencesLoader,
  );
  Future<void> _achievementUpdates = Future<void>.value();
  Future<void> _pendingFeatureWrites = Future<void>.value();
  final List<_FeatureWriteFailure> _featureWriteFailures = [];
  bool _achievementsLoaded = false;
  bool _achievementsLoadFailed = false;
  bool _achievementsLoading = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = widget.audioController ?? GameAudioManager();
    _dailyChallengeStore = DailyChallengeStore(now: widget.dailyChallengesNow);
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
        _gemLane = (_lane + 1) % _orbitCount;
        _gemAngle = _angle;
      }),
      readShieldActive: () => _shield.isActive,
      readShieldRemaining: () => _shield.remaining,
      readHazardCount: () => _hazards.length,
      readScore: () => _score,
      readOrbitCount: () => _orbitCount,
      readRunState: () => _state,
      readTotalGems: () => _achievementStore.totalGems,
      readWalletBalance: () => _wallet.balance,
      readAchievementUnlocked: _achievementStore.isUnlocked,
      flushAchievements: _flushAchievements,
      readRunsStarted: () => _statisticsStore.runsStarted,
      readShieldAbsorptions: () => _statisticsStore.shieldAbsorptions,
      readLosses: () => _statisticsStore.losses,
      readSelectedSkin: () => _skinStore.selectedSkin,
      readSelectedOrbit: () => _appearanceStore.selectedOrbit,
      readSelectedCore: () => _appearanceStore.selectedCore,
      readSelectedTrail: () => _appearanceStore.selectedTrail,
      readSkinUnlocked: (id) =>
          id == ShipSkinId.defaultSkin || _wallet.owns('ship.${id.name}'),
      flushProgress: _flushProgress,
      enqueueFeatureWrite: _queueFeatureWrite,
    );
    _featureStoresReady = _loadFeatureStores();
    unawaited(_featureStoresReady);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _best = prefs.getInt(_survivalBestKey) ?? 0);
    });
  }

  Future<void> _loadFeatureStores() async {
    await _loadDailyChallenges();
    await _loadAchievements();
    try {
      await _wallet.load();
      if (!_achievementsLoaded) {
        throw StateError('Lifetime gem progress is unavailable.');
      }
      await _statisticsStore.load();
      await _skinStore.load(ownedItemIds: _wallet.purchasedItemIds);
      await _appearanceStore.load(ownedItemIds: _wallet.purchasedItemIds);
      if (mounted) {
        setState(() {
          _featureStoresLoaded = true;
          _featureStoreLoadFailed = false;
        });
      }
    } catch (error) {
      debugPrint('Failed to load skin and statistics progress: $error');
      if (mounted) setState(() => _featureStoreLoadFailed = true);
    }
  }

  Future<void> _loadDailyChallenges() async {
    try {
      await _dailyChallengeStore.load();
      _dailyChallengesLoaded = true;
      _dailyChallengesLoadFailed = false;
    } catch (error) {
      debugPrint('Failed to load daily challenges: $error');
      _dailyChallengesLoaded = false;
      _dailyChallengesLoadFailed = true;
    }
  }

  void _retryFeatureStores() {
    _featureStoresReady = _loadFeatureStores();
    unawaited(_featureStoresReady);
  }

  Future<void> _flushProgress() async {
    await _featureStoresReady;
    await _flushAchievements();
    await _pendingFeatureWrites;
    await _statisticsStore.flush();
    await _skinStore.flush();
    await _appearanceStore.flush();
    await _wallet.flush();
    await _dailyChallengeStore.flush();
    if (_featureWriteFailures.isNotEmpty) {
      final failure = _featureWriteFailures.removeAt(0);
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  void _queueFeatureWrite(Future<void> Function() write) {
    _pendingFeatureWrites = _pendingFeatureWrites
        .then((_) => write())
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Queued feature write failed: $error');
          _featureWriteFailures.add(_FeatureWriteFailure(error, stackTrace));
        });
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
              Expanded(
                child: Text(
                  '${definition.title} unlocked!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
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
            hazardLaneForScore(_score, _lane, _orbitCount),
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
            _queueFeatureWrite(_recordShieldAbsorption);
            _queueFeatureWrite(
              () => _recordDailyChallengeEvent(
                DailyChallengeEvent.shieldAbsorbed,
              ),
            );
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
        _orbitCount = survivalOrbitCountForScore(_score);
        _highestOrbitCount = math.max(_highestOrbitCount, _orbitCount);
        final placement = randomizedGemPlacement(
          orbitCount: _orbitCount,
          random: _random,
          avoidAngle: _angle,
        );
        _gemAngle = placement.angle;
        _gemLane = placement.lane;
        _queueAchievementUpdate(_recordGemProgress());
        final pickupId = 'pickup:$_runToken:${++_pickupSequence}';
        _queueFeatureWrite(() async {
          await _wallet.creditPickupOnce(pickupId, 1);
        });
        _queueFeatureWrite(
          () => _recordDailyChallengeEvent(DailyChallengeEvent.gemCollected),
        );
        _queueAchievementUpdate(
          _achievementStore.recordRunProgress(_score, _highestOrbitCount),
        );
        if (_score == 10) {
          _queueFeatureWrite(
            () => _recordDailyChallengeEvent(DailyChallengeEvent.orbitReached),
          );
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
      _random.nextInt(_orbitCount),
    );
  }

  void _start() {
    if (_state == RunState.playing) return;
    setState(() {
      _orbitCount = 2;
      _highestOrbitCount = 2;
      _wallet.beginPickupSession();
      _runToken = DateTime.now().microsecondsSinceEpoch;
      _pickupSequence = 0;
      _score = 0;
      _lane = 0;
      _angle = -math.pi / 2;
      _spawnClock = 0;
      _hazards.clear();
      _shield.reset();
      _shieldPickup = null;
      _shieldSpawnClock = 0;
      _nextShieldSpawnAt = 12 + _random.nextDouble() * 8;
      final placement = randomizedGemPlacement(
        orbitCount: _orbitCount,
        random: _random,
        avoidAngle: _angle,
      );
      _gemAngle = placement.angle;
      _gemLane = placement.lane;
      _newRecord = false;
      _state = RunState.playing;
      _lastTick = Duration.zero;
    });
    _ticker.start();
    _audio.setGameState(AudioRunState.playing);
    _audio.playEffect(GameSoundEffect.start);
    _queueFeatureWrite(_recordRunStarted);
    _queueFeatureWrite(
      () => _recordDailyChallengeEvent(DailyChallengeEvent.runStarted),
    );
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
    _queueFeatureWrite(
      () => _statisticsStore.recordSurvivalRun(_score, _highestOrbitCount),
    );
    _queueFeatureWrite(_recordLoss);
  }

  void _saveBestScore() {
    if (_score <= _best) return;
    _best = _score;
    _newRecord = true;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(_survivalBestKey, _best),
      ),
    );
  }

  Future<List<AchievementId>> _recordGemProgress() async {
    final newlyUnlocked = await _achievementStore.recordGem();
    return newlyUnlocked;
  }

  Future<void> _recordRunStarted() async {
    try {
      await _statisticsStore.recordRunStarted();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save started-run statistic: $error');
    }
  }

  Future<void> _recordShieldAbsorption() async {
    try {
      await _statisticsStore.recordShieldAbsorption();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save shield statistic: $error');
    }
  }

  Future<void> _recordLoss() async {
    try {
      await _statisticsStore.recordLoss();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save loss statistic: $error');
    }
  }

  Future<void> _recordDailyChallengeEvent(DailyChallengeEvent event) async {
    try {
      await _dailyChallengeStore.recordEvent(event);
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save daily challenge progress: $error');
    }
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

  void _openAchievements() {
    setState(() => _state = RunState.achievements);
    _audio.setGameState(AudioRunState.menu);
  }

  void _openSkins() {
    setState(() {
      _state = RunState.skins;
      _selectedShopCategory = CosmeticShopCategory.ship;
    });
    _audio.setGameState(AudioRunState.menu);
  }

  void _openStatistics() {
    setState(() => _state = RunState.statistics);
    _audio.setGameState(AudioRunState.menu);
  }

  void _openDailyChallenges() {
    setState(() {
      _state = RunState.dailyChallenges;
      _dailyChallengesLoaded = false;
      _dailyChallengesLoadFailed = false;
    });
    _audio.setGameState(AudioRunState.menu);
    unawaited(_refreshDailyChallenges());
  }

  Future<void> _refreshDailyChallenges() async {
    await _loadDailyChallenges();
    if (mounted) setState(() {});
  }

  Future<void> _claimDailyChallengeReward(String id) async {
    try {
      final date = _dailyChallengeStore.dateKey;
      await _dailyChallengeStore.claimReward(
        id,
        onGrant: (reward) async {
          final credited = await _wallet.creditDailyRewardOnce(
            dateKey: date,
            challengeId: id,
            amount: reward,
          );
          return credited || _wallet.hasDailyReward(date, id);
        },
      );
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to claim daily challenge reward: $error');
    }
  }

  Future<void> _selectSkin(ShipSkinId id) async {
    final skin = shipSkins.firstWhere((item) => item.id == id);
    final owned = id == ShipSkinId.defaultSkin || _wallet.owns(skin.itemId);
    if (!owned) {
      await _purchaseSkin(skin);
      return;
    }
    try {
      final selected = await _skinStore.select(
        id,
        ownedItemIds: {'ship.defaultSkin', ..._wallet.purchasedItemIds},
      );
      if (selected && mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save selected ship skin: $error');
    }
  }

  Future<void> _purchaseSkin(ShipSkin skin) async {
    if (_purchaseInProgress || skin.price <= 0 || _wallet.owns(skin.itemId)) {
      return;
    }
    _purchaseInProgress = true;
    try {
      final purchased = await _wallet.purchase(
        itemId: skin.itemId,
        price: skin.price,
      );
      if (purchased && mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to purchase ship skin: $error');
    } finally {
      _purchaseInProgress = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectOrbitSkin(OrbitSkinId id) async {
    final skin = orbitSkins.firstWhere((item) => item.id == id);
    if (id != OrbitSkinId.defaultOrbit && !_wallet.owns(skin.itemId)) {
      if (_purchaseInProgress) return;
      _purchaseInProgress = true;
      try {
        await _wallet.purchase(itemId: skin.itemId, price: skin.price);
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('Failed to purchase orbit skin: $error');
      } finally {
        _purchaseInProgress = false;
        if (mounted) setState(() {});
      }
      return;
    }
    try {
      final selected = await _appearanceStore.selectOrbit(
        id,
        ownedItemIds: _wallet.purchasedItemIds,
      );
      if (selected && mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save selected orbit skin: $error');
    }
  }

  Future<void> _selectCoreSkin(CoreSkinId id) async {
    final skin = coreSkins.firstWhere((item) => item.id == id);
    if (id != CoreSkinId.defaultCore && !_wallet.owns(skin.itemId)) {
      if (_purchaseInProgress) return;
      _purchaseInProgress = true;
      try {
        await _wallet.purchase(itemId: skin.itemId, price: skin.price);
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('Failed to purchase core skin: $error');
      } finally {
        _purchaseInProgress = false;
        if (mounted) setState(() {});
      }
      return;
    }
    try {
      final selected = await _appearanceStore.selectCore(
        id,
        ownedItemIds: _wallet.purchasedItemIds,
      );
      if (selected && mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save selected core skin: $error');
    }
  }

  Future<void> _selectTrailSkin(TrailSkinId id) async {
    final skin = trailSkins.firstWhere((item) => item.id == id);
    if (id != TrailSkinId.classic && !_wallet.owns(skin.itemId)) {
      if (_purchaseInProgress) return;
      _purchaseInProgress = true;
      try {
        await _wallet.purchase(itemId: skin.itemId, price: skin.price);
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('Failed to purchase trail skin: $error');
      } finally {
        _purchaseInProgress = false;
        if (mounted) setState(() {});
      }
      return;
    }
    try {
      final selected = await _appearanceStore.selectTrail(
        id,
        ownedItemIds: _wallet.purchasedItemIds,
      );
      if (selected && mounted) setState(() {});
    } catch (error) {
      debugPrint('Failed to save selected trail skin: $error');
    }
  }

  void _tapGame(Offset globalPosition) {
    if (_state == RunState.playing) {
      final canvas =
          _orbitCanvasKey.currentContext!.findRenderObject()! as RenderBox;
      final selectedLane = laneAfterOrbitTouch(
        _lane,
        OrbitGeometry.forSizeAndCount(canvas.size, orbitCount: _orbitCount),
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
    RunState.achievements ||
    RunState.skins ||
    RunState.statistics ||
    RunState.dailyChallenges => AudioRunState.menu,
    RunState.playing => AudioRunState.playing,
    RunState.paused => AudioRunState.paused,
    RunState.over => AudioRunState.over,
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
          final compactHud =
              constraints.maxWidth < 360 || constraints.maxHeight < 600;
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff1b2233),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x66ffd66e)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.diamond_rounded,
                            color: Color(0xffffd66e),
                            size: 17,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${_wallet.balance} G',
                            key: const ValueKey('main-menu-gem-balance'),
                            style: const TextStyle(
                              color: Color(0xffffd66e),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
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
                    if (_state == RunState.ready)
                      IconButton(
                        onPressed: _openDailyChallenges,
                        tooltip: 'Daily challenges',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          color: Color(0xff65eaff),
                        ),
                      ),
                    if (_state == RunState.ready) ...[
                      IconButton(
                        onPressed: _openSkins,
                        tooltip: 'Cosmetic shop',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.palette_rounded,
                          color: _skinColor(_skinStore.selectedSkin),
                        ),
                      ),
                      IconButton(
                        onPressed: _openStatistics,
                        tooltip: 'Player statistics',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.query_stats_rounded,
                          color: Color(0xff65eaff),
                        ),
                      ),
                    ],
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
                          child: KeyedSubtree(
                            key: ValueKey(
                              'orbit-style-${_appearanceStore.selectedOrbit.name}-${_appearanceStore.selectedCore.name}',
                            ),
                            child: CustomPaint(
                              key: _shield.isActive
                                  ? const ValueKey('shield-aura-visible')
                                  : null,
                              size: Size.square(side),
                              painter: _OrbitPainter(
                                angle: _angle,
                                lane: _lane,
                                orbitCount: _orbitCount,
                                hazards: List.of(_hazards),
                                gemAngle: _gemAngle,
                                gemLane: _gemLane,
                                shieldAngle: _shieldPickup?.angle,
                                shieldLane: _shieldPickup?.lane,
                                shieldActive: _shield.isActive,
                                playerSkin: _skinStore.selectedSkin,
                                trailSkin: _appearanceStore.selectedTrail,
                                orbitSkin: _appearanceStore.selectedOrbit,
                                coreSkin: _appearanceStore.selectedCore,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_state == RunState.playing)
                        Positioned(
                          top: 2,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'SURVIVAL | ORBITS $_orbitCount | $_score GEMS',
                                  key: const ValueKey('survival-status'),
                                  style: TextStyle(
                                    color: Color(0xffdce7f7),
                                    letterSpacing: 0.8,
                                    fontSize: compactHud ? 9 : 10,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        color: Color(0xaa000000),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '$_score',
                                  key: const ValueKey('score'),
                                  style: TextStyle(
                                    fontSize: compactHud ? 42 : 48,
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
    if (_state == RunState.achievements) {
      return _achievementContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }
    if (_state == RunState.skins) {
      return _skinsContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }
    if (_state == RunState.statistics) {
      return _statisticsContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }
    if (_state == RunState.dailyChallenges) {
      return _dailyChallengesContent(
        compact: compact,
        showAudioControls: showAudioControls,
      );
    }

    final lost = _state == RunState.over;
    final spacing = compact ? 10.0 : 14.0;
    final title = ready
        ? 'READY, PILOT?'
        : paused
        ? 'PAUSED'
        : lost
        ? 'RUN OVER'
        : 'RUN OVER';
    final subtitle = ready
        ? 'Dodge the red. Chase the glow.'
        : paused
        ? 'Your orbit is on hold.'
        : lost
        ? 'You collected $_score gems and reached $_highestOrbitCount orbits.'
        : 'Survive, collect gems, and unlock more orbits.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready
              ? Icons.auto_awesome_rounded
              : paused
              ? Icons.pause_circle_outline_rounded
              : lost
              ? Icons.sports_score_rounded
              : Icons.sports_score_rounded,
          color: lost
              ? const Color(0xffff7180)
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
            'SURVIVAL | STARTING ORBITS: 2',
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
            'ORBIT UNLOCKS AT 10, 25, AND 45 GEMS',
            style: const TextStyle(
              color: Color(0xff8c9bb5),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          _resultCard(label: 'BEST SURVIVAL', value: '$_best'),
        ],
        if (paused) ...[
          SizedBox(height: spacing),
          _resultCard(label: 'CURRENT SCORE', value: '$_score'),
          const SizedBox(height: 6),
          Text(
            'SURVIVAL | $_orbitCount ORBITS',
            style: const TextStyle(color: Color(0xff8c9bb5), fontSize: 10),
          ),
        ],
        if (lost) ...[
          SizedBox(height: compact ? 8 : 12),
          Text(
            'GEMS COLLECTED',
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
          Text(
            'HIGHEST ORBIT: $_highestOrbitCount',
            style: const TextStyle(color: Color(0xff65eaff), fontSize: 10),
          ),
          if (_newRecord)
            const Text(
              'NEW SURVIVAL RECORD!',
              style: TextStyle(
                color: Color(0xffffd66e),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          SizedBox(height: compact ? 6 : 10),
          _resultCard(label: 'BEST SURVIVAL', value: '$_best'),
        ],
        if (showAudioControls && !lost) ...[
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
              ? 'RETRY RUN'
              : 'PLAY AGAIN',
          onPressed: ready
              ? _start
              : paused
              ? _resume
              : _start,
        ),
        if (ready || paused || lost) ...[
          const SizedBox(height: 8),
          _secondaryButton(
            label: ready
                ? 'ACHIEVEMENTS'
                : paused
                ? 'RESTART RUN'
                : 'MAIN MENU',
            icon: ready
                ? Icons.emoji_events_rounded
                : paused
                ? Icons.replay_rounded
                : Icons.home_rounded,
            onPressed: ready
                ? _openAchievements
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
            'Loading saved progress...',
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
      AchievementId.orbitExplorer || AchievementId.survivalOrbit3 =>
        '${math.min(_highestOrbitCount, 3)}/3 orbits reached this run',
      AchievementId.orbitalMaster || AchievementId.survivalOrbit5 =>
        unlocked ? 'Five orbits reached' : 'Reach five orbits in one run',
      AchievementId.survivalOrbit4 =>
        '${math.min(_highestOrbitCount, 4)}/4 orbits reached this run',
      AchievementId.survivalRun10 ||
      AchievementId.survivalRun25 => 'Run goal: ${achievement.gemGoal} gems',
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

  Widget _skinsContent({
    required bool compact,
    required bool showAudioControls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.palette_rounded,
        color: _skinColor(_skinStore.selectedSkin),
        size: 32,
      ),
      SizedBox(height: compact ? 7 : 10),
      Text(
        'COSMETIC SHOP',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 16 : 18,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      const Text(
        'Choose a look. Every skin plays the same.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xffaebbd2), fontSize: 11),
      ),
      const SizedBox(height: 7),
      Text(
        'GEMS  ${_wallet.balance}',
        key: const ValueKey('wallet-balance'),
        style: const TextStyle(
          color: Color(0xffffd66e),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      SizedBox(height: compact ? 9 : 12),
      if (!_featureStoresLoaded)
        _progressStoreMessage()
      else ...[
        _cosmeticCategoryTabs(),
        _cosmeticSectionTitle(_selectedShopCategory.sectionTitle),
        if (_selectedShopCategory == CosmeticShopCategory.ship)
          for (final skin in _skinsByRarity(shipSkins, (skin) => skin.rarity))
            _cosmeticItemWithPreview(
              key: 'ship-${skin.id.name}',
              name: skin.name,
              option: _skinOption(skin),
              onPreview: () => _showCosmeticPreview(
                name: skin.name,
                category: CosmeticShopCategory.ship,
                rarity: skin.rarity,
                playerSkin: skin.id,
                trailSkin: _appearanceStore.selectedTrail,
                orbitSkin: _appearanceStore.selectedOrbit,
                coreSkin: _appearanceStore.selectedCore,
              ),
            )
        else if (_selectedShopCategory == CosmeticShopCategory.orbit)
          for (final skin in _skinsByRarity(orbitSkins, (skin) => skin.rarity))
            _cosmeticItemWithPreview(
              key: 'orbit-${skin.id.name}',
              name: skin.name,
              option: _appearanceOption(
                key: 'orbit-option-${skin.id.name}',
                name: skin.name,
                description: skin.description,
                rarity: skin.rarity,
                price: skin.price,
                owned:
                    skin.id == OrbitSkinId.defaultOrbit ||
                    _wallet.owns(skin.itemId),
                selected: _appearanceStore.selectedOrbit == skin.id,
                accent: _orbitColor(skin.id),
                onSelect: () => _selectOrbitSkin(skin.id),
              ),
              onPreview: () => _showCosmeticPreview(
                name: skin.name,
                category: CosmeticShopCategory.orbit,
                rarity: skin.rarity,
                playerSkin: _skinStore.selectedSkin,
                trailSkin: _appearanceStore.selectedTrail,
                orbitSkin: skin.id,
                coreSkin: _appearanceStore.selectedCore,
              ),
            )
        else if (_selectedShopCategory == CosmeticShopCategory.core)
          for (final skin in _skinsByRarity(coreSkins, (skin) => skin.rarity))
            _cosmeticItemWithPreview(
              key: 'core-${skin.id.name}',
              name: skin.name,
              option: _appearanceOption(
                key: 'core-option-${skin.id.name}',
                name: skin.name,
                description: skin.description,
                rarity: skin.rarity,
                price: skin.price,
                owned:
                    skin.id == CoreSkinId.defaultCore ||
                    _wallet.owns(skin.itemId),
                selected: _appearanceStore.selectedCore == skin.id,
                accent: _coreColor(skin.id),
                onSelect: () => _selectCoreSkin(skin.id),
              ),
              onPreview: () => _showCosmeticPreview(
                name: skin.name,
                category: CosmeticShopCategory.core,
                rarity: skin.rarity,
                playerSkin: _skinStore.selectedSkin,
                trailSkin: _appearanceStore.selectedTrail,
                orbitSkin: _appearanceStore.selectedOrbit,
                coreSkin: skin.id,
              ),
            )
        else if (_selectedShopCategory == CosmeticShopCategory.trail)
          for (final skin in _skinsByRarity(trailSkins, (skin) => skin.rarity))
            _cosmeticItemWithPreview(
              key: 'trail-${skin.id.name}',
              name: skin.name,
              option: _appearanceOption(
                key: 'trail-option-${skin.id.name}',
                name: skin.name,
                description: skin.description,
                rarity: skin.rarity,
                price: skin.price,
                owned:
                    skin.id == TrailSkinId.classic || _wallet.owns(skin.itemId),
                selected: _appearanceStore.selectedTrail == skin.id,
                accent: _trailColor(skin.id),
                onSelect: () => _selectTrailSkin(skin.id),
              ),
              onPreview: () => _showCosmeticPreview(
                name: skin.name,
                category: CosmeticShopCategory.trail,
                rarity: skin.rarity,
                playerSkin: _skinStore.selectedSkin,
                trailSkin: skin.id,
                orbitSkin: _appearanceStore.selectedOrbit,
                coreSkin: _appearanceStore.selectedCore,
              ),
            ),
      ],
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

  Widget _cosmeticItemWithPreview({
    required String key,
    required String name,
    required Widget option,
    required VoidCallback onPreview,
  }) => Row(
    children: [
      Expanded(child: option),
      IconButton(
        key: ValueKey('preview-$key'),
        tooltip: 'Preview $name',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 48),
        onPressed: onPreview,
        icon: const Icon(
          Icons.visibility_rounded,
          color: Color(0xff65eaff),
          size: 19,
        ),
      ),
    ],
  );

  void _showCosmeticPreview({
    required String name,
    required CosmeticShopCategory category,
    required CosmeticRarity rarity,
    required ShipSkinId playerSkin,
    required TrailSkinId trailSkin,
    required OrbitSkinId orbitSkin,
    required CoreSkinId coreSkin,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => _CosmeticPreviewDialog(
        name: name,
        category: category,
        rarity: rarity,
        playerSkin: playerSkin,
        trailSkin: trailSkin,
        orbitSkin: orbitSkin,
        coreSkin: coreSkin,
      ),
    );
  }

  List<T> _skinsByRarity<T>(
    List<T> skins,
    CosmeticRarity Function(T) rarityOf,
  ) => [
    ...skins.where((skin) => rarityOf(skin) == CosmeticRarity.standard),
    ...skins.where((skin) => rarityOf(skin) == CosmeticRarity.premium),
  ];

  Widget _cosmeticCategoryTabs() => SingleChildScrollView(
    key: const ValueKey('cosmetic-category-tabs-scroll'),
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in CosmeticShopCategory.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox(
              width: 72,
              child: InkWell(
                key: ValueKey('cosmetic-tab-${category.name}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedShopCategory = category),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _selectedShopCategory == category
                        ? const Color(0x3355e7ff)
                        : const Color(0x221b2233),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedShopCategory == category
                          ? const Color(0x9955e7ff)
                          : const Color(0x337d8ba5),
                    ),
                  ),
                  child: Text(
                    category.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _selectedShopCategory == category
                          ? const Color(0xff65eaff)
                          : const Color(0xffaebbd2),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _cosmeticSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 5),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xff65eaff),
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );

  Widget _appearanceOption({
    required String key,
    required String name,
    required String description,
    required CosmeticRarity rarity,
    required int price,
    required bool owned,
    required bool selected,
    required Color accent,
    required Future<void> Function() onSelect,
  }) {
    final canAfford = _wallet.balance >= price;
    final state = selected
        ? 'EQUIPPED'
        : owned
        ? 'OWNED - EQUIP'
        : canAfford
        ? 'BUY - $price GEMS'
        : 'NEED ${price - _wallet.balance} MORE';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: OutlinedButton(
          key: ValueKey(key),
          onPressed: owned || canAfford ? () => unawaited(onSelect()) : null,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            side: BorderSide(
              color: selected
                  ? accent.withValues(alpha: .7)
                  : const Color(0x337d8ba5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Icon(
                owned ? Icons.auto_awesome_rounded : Icons.lock_outline,
                color: owned ? accent : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${rarity == CosmeticRarity.premium ? 'PREMIUM' : 'STANDARD'} | $price GEMS | $description',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff9baac3),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                state,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? accent
                      : owned
                      ? Colors.white70
                      : canAfford
                      ? const Color(0xffffd66e)
                      : Colors.white38,
                  fontSize: 8,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skinOption(ShipSkin skin) {
    final owned =
        skin.id == ShipSkinId.defaultSkin || _wallet.owns(skin.itemId);
    final selected = _skinStore.selectedSkin == skin.id;
    final canAfford = _wallet.balance >= skin.price;
    final state = selected
        ? 'EQUIPPED'
        : owned
        ? 'OWNED - EQUIP'
        : canAfford
        ? 'BUY - ${skin.price} GEMS'
        : 'NEED ${skin.price - _wallet.balance} MORE';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: OutlinedButton(
          key: ValueKey('skin-option-${skin.id.name}'),
          onPressed: owned || canAfford
              ? () => unawaited(_selectSkin(skin.id))
              : null,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white38,
            side: BorderSide(
              color: selected
                  ? _skinColor(skin.id).withValues(alpha: .7)
                  : const Color(0x337d8ba5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Icon(
                owned ? _skinIcon(skin.id) : Icons.lock_outline,
                color: owned ? _skinColor(skin.id) : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${skin.rarity == CosmeticRarity.premium ? 'PREMIUM' : 'STANDARD'} | ${skin.description}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff9baac3),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                state,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? _skinColor(skin.id)
                      : owned
                      ? Colors.white70
                      : canAfford
                      ? const Color(0xffffd66e)
                      : Colors.white38,
                  fontSize: 8,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statisticsContent({
    required bool compact,
    required bool showAudioControls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.query_stats_rounded, color: const Color(0xff65eaff), size: 32),
      SizedBox(height: compact ? 7 : 10),
      Text(
        'PLAYER STATISTICS',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 16 : 18,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: compact ? 9 : 12),
      if (!_featureStoresLoaded)
        _progressStoreMessage()
      else ...[
        _resultCard(
          label: 'LIFETIME GEMS',
          value: '${_achievementStore.totalGems}',
        ),
        const SizedBox(height: 6),
        _resultCard(label: 'BEST SCORE', value: '$_best'),
        const SizedBox(height: 6),
        _resultCard(
          label: 'BEST SURVIVAL RUN',
          value: '${_statisticsStore.bestRun}',
        ),
        const SizedBox(height: 6),
        _resultCard(
          label: 'MAX ORBITS REACHED',
          value: '${_statisticsStore.maxOrbit}',
        ),
        const SizedBox(height: 6),
        _resultCard(
          label: 'RUNS STARTED',
          value: '${_statisticsStore.runsStarted}',
        ),
        const SizedBox(height: 6),
        _resultCard(
          label: 'HIGHEST ORBIT THIS RUN',
          value: '$_highestOrbitCount',
        ),
        const SizedBox(height: 6),
        _resultCard(
          label: 'SHIELD COLLISIONS ABSORBED',
          value: '${_statisticsStore.shieldAbsorptions}',
        ),
        const SizedBox(height: 6),
        _resultCard(label: 'LOSSES', value: '${_statisticsStore.losses}'),
      ],
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

  Widget _dailyChallengesContent({
    required bool compact,
    required bool showAudioControls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.calendar_today_rounded,
        color: const Color(0xff65eaff),
        size: 32,
      ),
      SizedBox(height: compact ? 7 : 10),
      Text(
        'DAILY CHALLENGES',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 16 : 18,
          letterSpacing: 2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _dailyChallengeStore.dateKey,
        key: const ValueKey('daily-challenge-date'),
        style: const TextStyle(color: Color(0xff8c9bb5), fontSize: 10),
      ),
      const SizedBox(height: 4),
      Text(
        'GEMS  ${_wallet.balance}',
        key: const ValueKey('daily-wallet-balance'),
        style: const TextStyle(
          color: Color(0xffffd66e),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: compact ? 8 : 11),
      if (!_dailyChallengesLoaded)
        Column(
          children: [
            Text(
              _dailyChallengesLoadFailed
                  ? 'Could not load daily challenges. Saved progress is unchanged.'
                  : 'Loading daily challenges...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _dailyChallengesLoadFailed
                    ? const Color(0xffffb4a9)
                    : const Color(0xffaebbd2),
                fontSize: 11,
              ),
            ),
            if (_dailyChallengesLoadFailed)
              _secondaryButton(
                label: 'RETRY',
                icon: Icons.refresh_rounded,
                onPressed: () => unawaited(_refreshDailyChallenges()),
              ),
          ],
        )
      else ...[
        for (final challenge in _dailyChallengeStore.challenges)
          _dailyChallengeRow(challenge),
        Text(
          'Bonus gems granted: ${_dailyChallengeStore.bonusGemsGranted}',
          key: const ValueKey('daily-bonus-gems'),
          style: const TextStyle(color: Color(0xff8c9bb5), fontSize: 10),
        ),
      ],
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

  Widget _dailyChallengeRow(DailyChallenge challenge) {
    final definition = challenge.definition;
    final progressRatio = definition.goal <= 0
        ? 0.0
        : (challenge.progress / definition.goal).clamp(0.0, 1.0).toDouble();
    final displayedProgress = challenge.isComplete ? 1.0 : progressRatio;
    final status = challenge.rewardClaimed
        ? 'CLAIMED'
        : challenge.isComplete
        ? 'COMPLETE'
        : 'IN PROGRESS';
    return Container(
      key: ValueKey('daily-challenge-${definition.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff151e33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: challenge.isComplete
              ? const Color(0x6670e9ff)
              : const Color(0x337d8ba5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${challenge.progress} / ${definition.goal} - ${definition.gemReward} gems',
                  key: ValueKey('daily-progress-${definition.id}'),
                  style: const TextStyle(
                    color: Color(0xffaebbd2),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    key: ValueKey('daily-progress-bar-${definition.id}'),
                    value: displayedProgress,
                    minHeight: 4,
                    backgroundColor: const Color(0xff28334a),
                    color: const Color(0xff65eaff),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  key: ValueKey('daily-status-${definition.id}'),
                  style: TextStyle(
                    color: challenge.isComplete
                        ? const Color(0xff65eaff)
                        : Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              key: ValueKey('daily-claim-${definition.id}'),
              onPressed: challenge.isComplete && !challenge.rewardClaimed
                  ? () => unawaited(_claimDailyChallengeReward(definition.id))
                  : null,
              child: Text(challenge.rewardClaimed ? 'CLAIMED' : 'CLAIM'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _skinIcon(ShipSkinId id) => switch (id) {
    ShipSkinId.defaultSkin => Icons.blur_circular_rounded,
    ShipSkinId.emerald => Icons.diamond_rounded,
    ShipSkinId.nebula => Icons.auto_awesome_rounded,
    ShipSkinId.solar => Icons.wb_sunny_rounded,
    ShipSkinId.supernova => Icons.flare_rounded,
    ShipSkinId.obsidian => Icons.hexagon_rounded,
    ShipSkinId.prism => Icons.diamond_outlined,
    ShipSkinId.inferno => Icons.local_fire_department_rounded,
    ShipSkinId.frostbite => Icons.ac_unit_rounded,
    ShipSkinId.phantom => Icons.nights_stay_rounded,
  };

  Widget _progressStoreMessage() => Column(
    children: [
      Text(
        _featureStoreLoadFailed
            ? 'Could not load saved progress. Existing data was left unchanged.'
            : 'Loading saved progress...',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _featureStoreLoadFailed
              ? const Color(0xffffb4a9)
              : const Color(0xffaebbd2),
          fontSize: 11,
        ),
      ),
      if (_featureStoreLoadFailed) ...[
        const SizedBox(height: 8),
        _secondaryButton(
          label: 'RETRY',
          icon: Icons.refresh_rounded,
          onPressed: _retryFeatureStores,
        ),
      ],
    ],
  );

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
  static const _spectrumColors = [
    Color(0xffff68d2),
    Color(0xff51eaff),
    Color(0xffffd45c),
  ];
  static final Map<TrailSkinId, List<Paint>> _trailParticlePaints = {
    for (final entry in trailVisualStyles.entries)
      entry.key: List<Paint>.generate(3, (index) {
        final color = entry.value.pattern == TrailPattern.spectrum
            ? _spectrumColors[index]
            : Color(entry.value.color);
        return Paint()
          ..color = color.withValues(
            alpha: entry.value.particleAlpha + .06 * index,
          );
      }),
  };
  static final Map<TrailSkinId, List<Paint>> _trailGlowPaints = {
    for (final entry in trailVisualStyles.entries)
      entry.key: List<Paint>.generate(3, (index) {
        final color = entry.value.pattern == TrailPattern.spectrum
            ? _spectrumColors[index]
            : Color(entry.value.color);
        return Paint()
          ..color = color.withValues(
            alpha: entry.value.glowAlpha * (index + 1) / 3,
          );
      }),
  };
  static final Map<TrailSkinId, Paint> _trailAccentPaints = {
    for (final entry in trailVisualStyles.entries)
      entry.key: Paint()
        ..color = Color(entry.value.accentColor).withValues(alpha: .86),
  };
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
    required this.playerSkin,
    required this.trailSkin,
    required this.orbitSkin,
    required this.coreSkin,
  });
  final double angle, gemAngle;
  final int lane, gemLane, orbitCount;
  final List<_Hazard> hazards;
  final double? shieldAngle;
  final int? shieldLane;
  final bool shieldActive;
  final ShipSkinId playerSkin;
  final TrailSkinId trailSkin;
  final OrbitSkinId orbitSkin;
  final CoreSkinId coreSkin;

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
    final orbitColors = _orbitPalette(orbitSkin);
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
          ..color = orbitColors.glow.withValues(alpha: .055)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = orbitColors.stroke.withValues(alpha: .64)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35,
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = orbitColors.highlight.withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .55,
      );
      if (orbitColors.pattern == OrbitPattern.prism) {
        const prismColors = [
          Color(0xffff6fcf),
          Color(0xffffc857),
          Color(0xffa5ff79),
          Color(0xff50e6ff),
          Color(0xff7284ff),
          Color(0xffc678ff),
        ];
        for (var i = 0; i < prismColors.length; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: r),
            i * _fullTurn / prismColors.length,
            _fullTurn / prismColors.length * .72,
            false,
            Paint()
              ..color = prismColors[i].withValues(alpha: .85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7,
          );
        }
      } else if (orbitColors.pattern == OrbitPattern.eclipse) {
        _drawEclipseOrbit(canvas, center, r, orbitColors);
      } else if (orbitColors.pattern == OrbitPattern.plasma) {
        _drawPlasmaOrbit(canvas, center, r, orbitColors);
      }
    }
    _orbitMarkers(canvas, center, geometry.radii);
    _planet(canvas, center, radius * (orbitCount == 2 ? .40 : .10));
    if (shieldActive) {
      _shieldAura(canvas, center, geometry.radiusForLane(lane), angle);
    }
    _playerShip(canvas, center, geometry.radiusForLane(lane), angle);
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

  void _drawEclipseOrbit(
    Canvas canvas,
    Offset center,
    double radius,
    _OrbitColors colors,
  ) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      bounds,
      -math.pi * .82,
      math.pi * .72,
      false,
      Paint()
        ..color = colors.glow.withValues(alpha: .78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawArc(
      bounds,
      math.pi * .18,
      math.pi * .52,
      false,
      Paint()
        ..color = colors.highlight.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawArc(
      bounds,
      math.pi * .36,
      math.pi * .2,
      false,
      Paint()
        ..color = colors.stroke.withValues(alpha: .95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
  }

  void _drawPlasmaOrbit(
    Canvas canvas,
    Offset center,
    double radius,
    _OrbitColors colors,
  ) {
    Offset point(double angle, double radialOffset) =>
        center +
        Offset(
          math.cos(angle) * (radius + radialOffset),
          math.sin(angle) * (radius + radialOffset),
        );

    final arcPaint = Paint()
      ..color = colors.highlight.withValues(alpha: .92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final sparkPaint = Paint()..color = colors.marker.withValues(alpha: .9);
    for (var i = 0; i < 8; i++) {
      final start = i * _fullTurn / 8;
      final step = _fullTurn / 32;
      final path = Path()
        ..moveTo(point(start, -1.5).dx, point(start, -1.5).dy)
        ..lineTo(point(start + step, 1.7).dx, point(start + step, 1.7).dy)
        ..lineTo(
          point(start + step * 2, -.8).dx,
          point(start + step * 2, -.8).dy,
        )
        ..lineTo(
          point(start + step * 3, 1.4).dx,
          point(start + step * 3, 1.4).dy,
        )
        ..lineTo(point(start + step * 4, 0).dx, point(start + step * 4, 0).dy);
      canvas.drawPath(path, arcPaint);
      final spark = point(start + step * 2, -.8);
      canvas.drawCircle(spark, 1.15, sparkPaint);
    }
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
    final colors = _orbitPalette(orbitSkin);
    final paint = Paint()
      ..color = colors.marker.withValues(alpha: .35)
      ..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final angle = i * _fullTurn / 12;
      if (colors.pattern == OrbitPattern.prism) {
        const markerColors = [
          Color(0xffff6fcf),
          Color(0xffffc857),
          Color(0xffa5ff79),
          Color(0xff50e6ff),
          Color(0xff7284ff),
          Color(0xffc678ff),
        ];
        paint.color = markerColors[i % markerColors.length].withValues(
          alpha: .62,
        );
      } else if (colors.pattern == OrbitPattern.radiant) {
        paint.color = colors.marker.withValues(alpha: i.isEven ? .72 : .35);
      }
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
      if (colors.pattern == OrbitPattern.pulsar && i % 3 == 0) {
        for (final radius in radii) {
          final pulse =
              center +
              Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          canvas.drawCircle(
            pulse,
            1.7,
            Paint()..color = colors.highlight.withValues(alpha: .9),
          );
        }
      } else if (colors.pattern == OrbitPattern.ion && i % 4 == 0) {
        for (final radius in radii) {
          final spark =
              center +
              Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          canvas.drawLine(
            spark + const Offset(-2, 0),
            spark + const Offset(2, 0),
            Paint()
              ..color = colors.highlight
              ..strokeWidth = 1.2,
          );
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
    final colors = _corePalette(coreSkin);
    c.drawCircle(
      center,
      r * 1.25,
      Paint()..color = colors.glow.withValues(alpha: .11),
    );
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-.4, -.5),
          colors: colors.gradient,
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
          ..color = colors.band.withValues(alpha: .13)
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
        Paint()..color = colors.crater.withValues(alpha: .28),
      );
      c.drawArc(
        Rect.fromCircle(center: craterCenter, radius: r * .095),
        math.pi * 1.1,
        math.pi * .9,
        false,
        Paint()
          ..color = colors.craterRim.withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .65,
      );
    }
    switch (colors.detail) {
      case CoreDetail.classic:
        break;
      case CoreDetail.toxic:
        for (final bubble in [
          const Offset(-.42, .12),
          const Offset(.38, -.32),
          const Offset(.08, .46),
        ]) {
          final point = center + Offset(bubble.dx * r, bubble.dy * r);
          c.drawCircle(
            point,
            r * .09,
            Paint()
              ..color = colors.highlight.withValues(alpha: .74)
              ..style = PaintingStyle.stroke
              ..strokeWidth = .8,
          );
          c.drawCircle(
            point + Offset(r * .025, -r * .025),
            r * .025,
            Paint()..color = colors.band.withValues(alpha: .8),
          );
        }
      case CoreDetail.voidCore:
        c.drawCircle(
          center + Offset(r * .12, r * .08),
          r * .3,
          Paint()..color = colors.crater.withValues(alpha: .82),
        );
        for (final spark in [
          const Offset(-.48, -.08),
          const Offset(.43, -.25),
          const Offset(-.12, .53),
        ]) {
          final point = center + Offset(spark.dx * r, spark.dy * r);
          c.drawCircle(
            point,
            r * .045,
            Paint()..color = colors.highlight.withValues(alpha: .9),
          );
        }
      case CoreDetail.magma:
        final cracks = [
          [
            const Offset(-.58, -.15),
            const Offset(-.2, -.08),
            const Offset(-.05, .1),
            const Offset(.28, .16),
          ],
          [
            const Offset(.05, -.58),
            const Offset(.1, -.22),
            const Offset(-.08, -.06),
            const Offset(-.18, .25),
          ],
        ];
        for (final points in cracks) {
          final crack = Path()
            ..moveTo(
              center.dx + points.first.dx * r,
              center.dy + points.first.dy * r,
            );
          for (final point in points.skip(1)) {
            crack.lineTo(center.dx + point.dx * r, center.dy + point.dy * r);
          }
          c.drawPath(
            crack,
            Paint()
              ..color = colors.highlight.withValues(alpha: .86)
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * .055,
          );
        }
      case CoreDetail.ocean:
        for (var i = 0; i < 3; i++) {
          final y = center.dy + (i - 1) * r * .38;
          final wave = Path()
            ..moveTo(center.dx - r, y)
            ..cubicTo(
              center.dx - r * .5,
              y - r * .22,
              center.dx + r * .1,
              y + r * .24,
              center.dx + r,
              y - r * .06,
            );
          c.drawPath(
            wave,
            Paint()
              ..color = colors.highlight.withValues(alpha: .36)
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * .07,
          );
        }
      case CoreDetail.rose:
        for (var i = 0; i < 5; i++) {
          final angle = i * _fullTurn / 5;
          final petal =
              center +
              Offset(math.cos(angle) * r * .48, math.sin(angle) * r * .48);
          c.drawCircle(
            petal,
            r * .12,
            Paint()
              ..color = colors.highlight.withValues(alpha: .36)
              ..style = PaintingStyle.stroke
              ..strokeWidth = .8,
          );
        }
      case CoreDetail.stellar:
        for (final star in [
          const Offset(-.38, -.28),
          const Offset(.36, -.1),
          const Offset(-.1, .43),
        ]) {
          final point = center + Offset(star.dx * r, star.dy * r);
          c.drawLine(
            point - Offset(r * .12, 0),
            point + Offset(r * .12, 0),
            Paint()
              ..color = colors.highlight.withValues(alpha: .85)
              ..strokeWidth = .8,
          );
          c.drawLine(
            point - Offset(0, r * .12),
            point + Offset(0, r * .12),
            Paint()
              ..color = colors.highlight.withValues(alpha: .85)
              ..strokeWidth = .8,
          );
          c.drawCircle(point, r * .035, Paint()..color = Colors.white);
        }
      case CoreDetail.quantum:
        final lattice = Path()
          ..moveTo(center.dx, center.dy - r * .55)
          ..lineTo(center.dx + r * .48, center.dy + r * .3)
          ..lineTo(center.dx - r * .48, center.dy + r * .3)
          ..close()
          ..moveTo(center.dx - r * .48, center.dy - r * .3)
          ..lineTo(center.dx + r * .48, center.dy - r * .3)
          ..lineTo(center.dx, center.dy + r * .55);
        c.drawPath(
          lattice,
          Paint()
            ..color = colors.highlight.withValues(alpha: .56)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .035,
        );
        c.drawCircle(
          center,
          r * .16,
          Paint()
            ..color = colors.band.withValues(alpha: .7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .05,
        );
    }
    c.restore();
    c.drawArc(
      Rect.fromCircle(center: center, radius: r - .8),
      math.pi * 1.08,
      math.pi * .72,
      false,
      Paint()
        ..color = colors.highlight.withValues(alpha: .48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    c.drawCircle(
      center,
      r,
      Paint()
        ..color = colors.outline.withValues(alpha: .35)
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

  void _playerShip(Canvas canvas, Offset center, double radius, double angle) {
    final position =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    final shipStyle = shipVisualStyles[playerSkin]!;
    final color = Color(shipStyle.color);
    final accent = Color(shipStyle.accent);
    final trailStyle = trailVisualStyles[trailSkin]!;
    final particlePaints = _trailParticlePaints[trailSkin]!;
    final glowPaints = _trailGlowPaints[trailSkin]!;
    for (var i = 3; i >= 1; i--) {
      final particleIndex = 3 - i;
      final trailAngle = angle - i * .055;
      final trailPoint =
          center +
          Offset(math.cos(trailAngle) * radius, math.sin(trailAngle) * radius);
      final particleRadius = 8 * (1 - i * .16);
      if (trailSkin != TrailSkinId.classic) {
        canvas.drawCircle(
          trailPoint,
          particleRadius * 1.8,
          glowPaints[particleIndex],
        );
      }
      canvas.drawCircle(
        trailPoint,
        particleRadius,
        particlePaints[particleIndex],
      );
      final accentPaint = _trailAccentPaints[trailSkin]!;
      switch (trailStyle.pattern) {
        case TrailPattern.classic:
        case TrailPattern.aurora:
        case TrailPattern.solar:
          break;
        case TrailPattern.frost:
          canvas.drawLine(
            trailPoint + const Offset(-1.8, -1.8),
            trailPoint + const Offset(1.8, 1.8),
            accentPaint,
          );
          canvas.drawLine(
            trailPoint + const Offset(-1.8, 1.8),
            trailPoint + const Offset(1.8, -1.8),
            accentPaint,
          );
        case TrailPattern.phantom:
          canvas.drawCircle(
            trailPoint + Offset(-particleRadius * .4, particleRadius * .3),
            particleRadius * .45,
            accentPaint,
          );
        case TrailPattern.electric:
          canvas.drawLine(
            trailPoint + const Offset(-2.8, .8),
            trailPoint + const Offset(2.8, -.8),
            accentPaint..strokeWidth = 1.2,
          );
        case TrailPattern.ember:
          canvas.drawCircle(
            trailPoint + Offset(particleRadius * .45, particleRadius * .5),
            particleRadius * .32,
            accentPaint,
          );
        case TrailPattern.stardust:
          canvas.drawCircle(
            trailPoint + const Offset(2, -1.8),
            .8,
            accentPaint,
          );
        case TrailPattern.toxic:
          canvas.drawCircle(
            trailPoint + Offset(-particleRadius * .45, -particleRadius * .4),
            particleRadius * .36,
            accentPaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = .65,
          );
        case TrailPattern.spectrum:
          canvas.drawCircle(
            trailPoint + const Offset(0, -2),
            particleRadius * .32,
            accentPaint,
          );
      }
    }
    canvas.drawCircle(
      position,
      13.2,
      Paint()..color = color.withValues(alpha: .16),
    );
    final path = Path();
    switch (shipStyle.silhouette) {
      case ShipSilhouette.orb:
        canvas.drawCircle(position, 8, Paint()..color = color);
        break;
      case ShipSilhouette.diamond:
        path
          ..moveTo(position.dx, position.dy - 8)
          ..lineTo(position.dx + 7, position.dy)
          ..lineTo(position.dx, position.dy + 8)
          ..lineTo(position.dx - 7, position.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
        break;
      case ShipSilhouette.nebula:
        canvas.drawCircle(
          position,
          7,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        canvas.drawCircle(position, 3, Paint()..color = color);
        canvas.drawCircle(
          position +
              Offset(
                math.cos(angle + math.pi / 2) * 6.5,
                math.sin(angle + math.pi / 2) * 6.5,
              ),
          1.6,
          Paint()..color = Colors.white,
        );
        break;
      case ShipSilhouette.solarStar:
        _shipStar(canvas, position, angle, color, points: 8, innerRadius: 5.5);
        break;
      case ShipSilhouette.supernova:
        _shipStar(canvas, position, angle, color, points: 10, innerRadius: 3.8);
        break;
      case ShipSilhouette.obsidian:
        path.addPolygon(_shipPolygon(position, angle, 6, 8, 8), true);
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawPath(
          path,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.35,
        );
        canvas.drawPath(
          Path()
            ..moveTo(position.dx, position.dy - 4)
            ..lineTo(position.dx + 3.5, position.dy)
            ..lineTo(position.dx, position.dy + 4)
            ..lineTo(position.dx - 3.5, position.dy)
            ..close(),
          Paint()..color = accent,
        );
        break;
      case ShipSilhouette.prism:
        final vertices = _shipPolygon(position, angle, 6, 8, 8);
        path.addPolygon(vertices, true);
        canvas.drawPath(path, Paint()..color = color);
        final facets = [
          const Color(0xffff71ce),
          const Color(0xffffd45e),
          const Color(0xff55f4db),
        ];
        for (var i = 0; i < 3; i++) {
          final facet = Path()
            ..moveTo(position.dx, position.dy)
            ..lineTo(vertices[i * 2].dx, vertices[i * 2].dy)
            ..lineTo(
              vertices[(i * 2 + 1) % vertices.length].dx,
              vertices[(i * 2 + 1) % vertices.length].dy,
            )
            ..close();
          canvas.drawPath(
            facet,
            Paint()..color = facets[i].withValues(alpha: .72),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        break;
      case ShipSilhouette.inferno:
        path
          ..moveTo(position.dx, position.dy - 9)
          ..quadraticBezierTo(
            position.dx + 8,
            position.dy - 3,
            position.dx + 5.5,
            position.dy + 5,
          )
          ..quadraticBezierTo(
            position.dx,
            position.dy + 10,
            position.dx - 5.5,
            position.dy + 5,
          )
          ..quadraticBezierTo(
            position.dx - 8,
            position.dy - 3,
            position.dx,
            position.dy - 9,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawPath(
          Path()
            ..moveTo(position.dx, position.dy - 4)
            ..quadraticBezierTo(
              position.dx + 4,
              position.dy + 1,
              position.dx,
              position.dy + 5,
            )
            ..quadraticBezierTo(
              position.dx - 3,
              position.dy + 1,
              position.dx,
              position.dy - 4,
            )
            ..close(),
          Paint()..color = accent,
        );
        break;
      case ShipSilhouette.frostbite:
        final crystal = _shipPolygon(position, angle, 8, 8, 2.8);
        path.addPolygon(crystal, true);
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawPath(
          path,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        for (var i = 0; i < 4; i++) {
          final tip = crystal[i * 2];
          canvas.drawLine(position, tip, Paint()..color = accent);
        }
        break;
      case ShipSilhouette.phantom:
        canvas.drawCircle(position, 7.5, Paint()..color = color);
        canvas.drawCircle(
          position + const Offset(4, -2),
          6.5,
          Paint()..color = const Color(0xff070b18),
        );
        canvas.drawArc(
          Rect.fromCircle(center: position, radius: 8.5),
          math.pi * .8,
          math.pi * 1.25,
          false,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(
          position + const Offset(-3, 2),
          1.3,
          Paint()..color = accent,
        );
        break;
    }
    canvas.drawCircle(
      position,
      2.8,
      Paint()..color = Colors.white.withValues(alpha: .92),
    );
  }

  List<Offset> _shipPolygon(
    Offset center,
    double rotation,
    int points,
    double outerRadius,
    double innerRadius,
  ) => [
    for (var i = 0; i < points; i++)
      center +
          Offset(
            math.cos(rotation + i * _fullTurn / points - math.pi / 2) *
                (i.isEven ? outerRadius : innerRadius),
            math.sin(rotation + i * _fullTurn / points - math.pi / 2) *
                (i.isEven ? outerRadius : innerRadius),
          ),
  ];

  void _shipStar(
    Canvas canvas,
    Offset center,
    double rotation,
    Color color, {
    required int points,
    required double innerRadius,
  }) {
    final path = Path();
    for (var i = 0; i < points; i++) {
      final radius = i.isEven ? 8.0 : innerRadius;
      final angle = rotation + i * math.pi / points - math.pi / 2;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
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

class _CosmeticPreviewDialog extends StatelessWidget {
  const _CosmeticPreviewDialog({
    required this.name,
    required this.category,
    required this.rarity,
    required this.playerSkin,
    required this.trailSkin,
    required this.orbitSkin,
    required this.coreSkin,
  });

  final String name;
  final CosmeticShopCategory category;
  final CosmeticRarity rarity;
  final ShipSkinId playerSkin;
  final TrailSkinId trailSkin;
  final OrbitSkinId orbitSkin;
  final CoreSkinId coreSkin;

  String get _sceneLabel =>
      'Preview scene: ship=${playerSkin.name}; orbit=${orbitSkin.name}; core=${coreSkin.name}; trail=${trailSkin.name}';

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xed0d1427),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0x9955e7ff)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sceneSize = math.min(220.0, constraints.maxWidth);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: const ValueKey('cosmetic-preview-close'),
                        tooltip: 'Close preview',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${category.label} | ${rarity == CosmeticRarity.premium ? 'PREMIUM' : 'STANDARD'}',
                      key: const ValueKey('cosmetic-preview-category-rarity'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xffffd66e),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: _sceneLabel,
                      child: RepaintBoundary(
                        key: const ValueKey('cosmetic-preview-scene'),
                        child: CustomPaint(
                          size: Size.square(sceneSize),
                          painter: _OrbitPainter(
                            angle: -math.pi / 2,
                            lane: 0,
                            orbitCount: 2,
                            hazards: const [],
                            gemAngle: math.pi / 3,
                            gemLane: 1,
                            shieldAngle: null,
                            shieldLane: null,
                            shieldActive: false,
                            playerSkin: playerSkin,
                            trailSkin: trailSkin,
                            orbitSkin: orbitSkin,
                            coreSkin: coreSkin,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Preview only. This does not purchase or equip the cosmetic.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xffaebbd2),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('BACK TO SHOP'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xff65eaff),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeatureWriteFailure {
  const _FeatureWriteFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _OrbitColors {
  const _OrbitColors(
    this.glow,
    this.stroke,
    this.marker,
    this.highlight,
    this.pattern,
  );
  final Color glow;
  final Color stroke;
  final Color marker;
  final Color highlight;
  final OrbitPattern pattern;
}

class _CoreColors {
  const _CoreColors({
    required this.glow,
    required this.gradient,
    required this.band,
    required this.crater,
    required this.craterRim,
    required this.highlight,
    required this.outline,
    required this.detail,
  });
  final Color glow;
  final List<Color> gradient;
  final Color band;
  final Color crater;
  final Color craterRim;
  final Color highlight;
  final Color outline;
  final CoreDetail detail;
}

final Map<OrbitSkinId, _OrbitColors> _orbitPalettes = {
  for (final entry in orbitVisualStyles.entries)
    entry.key: _OrbitColors(
      Color(entry.value.glow),
      Color(entry.value.stroke),
      Color(entry.value.marker),
      Color(entry.value.highlight),
      entry.value.pattern,
    ),
};

_OrbitColors _orbitPalette(OrbitSkinId skin) => _orbitPalettes[skin]!;

final Map<CoreSkinId, _CoreColors> _corePalettes = {
  for (final entry in coreVisualStyles.entries)
    entry.key: _CoreColors(
      glow: Color(entry.value.glow),
      gradient: entry.value.gradient.map(Color.new).toList(growable: false),
      band: Color(entry.value.band),
      crater: Color(entry.value.crater),
      craterRim: Color(entry.value.craterRim),
      highlight: Color(entry.value.highlight),
      outline: Color(entry.value.outline),
      detail: entry.value.detail,
    ),
};

_CoreColors _corePalette(CoreSkinId skin) => _corePalettes[skin]!;

Color _orbitColor(OrbitSkinId skin) => _orbitPalette(skin).glow;

Color _coreColor(CoreSkinId skin) => _corePalette(skin).outline;

extension on CosmeticShopCategory {
  String get label => switch (this) {
    CosmeticShopCategory.ship => 'SHIP',
    CosmeticShopCategory.orbit => 'ORBIT',
    CosmeticShopCategory.core => 'CORE',
    CosmeticShopCategory.trail => 'TRAIL',
  };

  String get sectionTitle => switch (this) {
    CosmeticShopCategory.ship => 'SHIP SKINS',
    CosmeticShopCategory.orbit => 'ORBIT SKINS',
    CosmeticShopCategory.core => 'CORE SKINS',
    CosmeticShopCategory.trail => 'TRAIL SKINS',
  };
}

Color _trailColor(TrailSkinId skin) => Color(trailVisualStyles[skin]!.color);

Color _skinColor(ShipSkinId skin) => Color(shipVisualStyles[skin]!.color);
