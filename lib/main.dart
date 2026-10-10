import 'dart:async';
import 'dart:math' as math;

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

enum RunState { ready, playing, paused, over }

const double _fullTurn = math.pi * 2;

double shortestAngularDistance(double first, double second) {
  final difference = (first - second).abs() % _fullTurn;
  return math.min(difference, _fullTurn - difference);
}

bool isAngularCollision(double first, double second) =>
    shortestAngularDistance(first, second) < 0.16;

bool hazardLifetimeExpired(double relativeAngleTravel) =>
    relativeAngleTravel >= _fullTurn;

double playerSpeedForScore(int score) => 1.55 + math.min(score * 0.035, 1.5);

double hazardSpawnIntervalForScore(int score) =>
    math.max(0.85, 2.0 - score * 0.025);

class OrbitGamePage extends StatefulWidget {
  const OrbitGamePage({super.key, this.audioController});

  final GameAudioController? audioController;

  @override
  State<OrbitGamePage> createState() => _OrbitGamePageState();
}

class _OrbitGamePageState extends State<OrbitGamePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameAudioController _audio;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  RunState _state = RunState.ready;
  int _score = 0;
  int _best = 0;
  int _lane = 0;
  double _angle = -math.pi / 2;
  double _gemAngle = 0.7;
  int _gemLane = 1;
  final List<_Hazard> _hazards = [];
  double _spawnClock = 0;

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
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _best = prefs.getInt('orbit_dash_best') ?? 0);
    });
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
      final speed = playerSpeedForScore(_score);
      _angle += speed * dt;
      _spawnClock += dt;
      if (_spawnClock > hazardSpawnIntervalForScore(_score)) {
        _spawnClock = 0;
        _hazards.add(
          _Hazard(
            (_angle + math.pi + 0.4) % (math.pi * 2),
            _score % 3 == 2 ? 1 - _lane : (_score % 2),
          ),
        );
      }
      for (final hazard in _hazards) {
        hazard.angle = (hazard.angle + speed * 0.7 * dt) % (math.pi * 2);
        if (hazard.lane == _lane && isAngularCollision(_angle, hazard.angle)) {
          _finish();
          return;
        }
        hazard.relativeAngleTravel += speed * 0.3 * dt;
      }
      _hazards.removeWhere((h) => hazardLifetimeExpired(h.relativeAngleTravel));
      final gemDifference = (_angle - _gemAngle).abs() % (2 * math.pi);
      if (_gemLane == _lane &&
          math.min(gemDifference, 2 * math.pi - gemDifference) < 0.12) {
        _score++;
        _audio.playEffect(GameSoundEffect.gemCollect);
        _gemAngle = (_angle + 2.4 + (_score % 3) * 0.45) % (math.pi * 2);
        _gemLane = 1 - _gemLane;
      }
    });
  }

  void _start() {
    setState(() {
      _score = 0;
      _lane = 0;
      _angle = -math.pi / 2;
      _spawnClock = 0;
      _hazards.clear();
      _gemAngle = 0.7;
      _gemLane = 1;
      _state = RunState.playing;
      _lastTick = Duration.zero;
    });
    _ticker.start();
    _audio.setGameState(AudioRunState.playing);
    _audio.playEffect(GameSoundEffect.start);
  }

  void _finish() {
    _state = RunState.over;
    _ticker.stop();
    _audio.setGameState(AudioRunState.over);
    _audio.playEffect(GameSoundEffect.collision);
    if (_score > _best) {
      _best = _score;
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt('orbit_dash_best', _best),
      );
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
    _lastTick = Duration.zero;
    setState(() => _state = RunState.ready);
    _audio.setGameState(AudioRunState.menu);
  }

  void _tapGame() {
    if (_state == RunState.playing) {
      setState(() => _lane = 1 - _lane);
      _audio.playEffect(GameSoundEffect.orbitSwitch);
    }
  }

  AudioRunState _audioStateFor(RunState state) => switch (state) {
    // The ready overlay is the app's actual start/menu screen.
    RunState.ready => AudioRunState.menu,
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
                  onTap: _tapGame,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: side,
                        height: side,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              key: ValueKey('orbit-lane-$_lane'),
                              size: Size.square(side),
                              painter: _OrbitPainter(
                                angle: _angle,
                                lane: _lane,
                                hazards: List.of(_hazards),
                                gemAngle: _gemAngle,
                                gemLane: _gemLane,
                              ),
                            ),
                            if (_state == RunState.playing)
                              Positioned(
                                top: 22,
                                child: Column(
                                  children: [
                                    const Text(
                                      'SCORE',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        letterSpacing: 2.5,
                                        fontSize: 11,
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
                          ],
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
                      'TAP TO SWITCH ORBITS',
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
    final spacing = compact ? 10.0 : 14.0;
    final title = ready
        ? 'READY, PILOT?'
        : paused
        ? 'PAUSED'
        : 'GAME OVER';
    final subtitle = ready
        ? 'Dodge the red. Chase the glow.'
        : paused
        ? 'Your orbit is on hold.'
        : 'You collected $_score ${_score == 1 ? 'shard' : 'shards'}.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready
              ? Icons.auto_awesome_rounded
              : paused
              ? Icons.pause_circle_outline_rounded
              : Icons.sports_score_rounded,
          color: paused
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
          _resultCard(label: 'BEST FLIGHT', value: '$_best'),
        ],
        if (paused) ...[
          SizedBox(height: spacing),
          _resultCard(label: 'CURRENT SCORE', value: '$_score'),
        ],
        if (!ready && !paused) ...[
          SizedBox(height: compact ? 8 : 12),
          const Text(
            'FINAL SCORE',
            style: TextStyle(
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
          SizedBox(height: compact ? 6 : 10),
          _resultCard(label: 'BEST FLIGHT', value: '$_best'),
        ],
        if (showAudioControls) ...[
          SizedBox(height: compact ? 8 : 12),
          Row(
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
          ),
        ],
        SizedBox(height: compact ? 14 : 20),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: paused ? _resume : _start,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff54e6ff),
              foregroundColor: const Color(0xff06101d),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              paused ? Icons.play_arrow_rounded : Icons.play_arrow_rounded,
              size: 23,
            ),
            label: Text(
              ready
                  ? 'START RUN'
                  : paused
                  ? 'RESUME'
                  : 'PLAY AGAIN',
              style: const TextStyle(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
        if (paused) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _start,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffc3d0e6),
                side: const BorderSide(color: Color(0x557d8ba5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.replay_rounded, size: 19),
              label: const Text(
                'RESTART RUN',
                style: TextStyle(
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
        if (!ready && !paused) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _returnToMenu,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffc3d0e6),
                side: const BorderSide(color: Color(0x557d8ba5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.home_rounded, size: 19),
              label: const Text(
                'MAIN MENU',
                style: TextStyle(
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

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
    required this.hazards,
    required this.gemAngle,
    required this.gemLane,
  });
  final double angle, gemAngle;
  final int lane, gemLane;
  final List<_Hazard> hazards;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      size.height / 2 + size.height * 0.035,
    );
    final radius = size.width * 0.34;
    final inner = radius * 0.72;
    final outer = radius;
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
    for (final r in [inner, outer]) {
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
    _orbitMarkers(canvas, center, inner, outer);
    _planet(canvas, center, radius * .40);
    _orbitalThing(
      canvas,
      center,
      lane == 0 ? inner : outer,
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
        hazard.lane == 0 ? inner : outer,
        hazard.angle,
        const Color(0xffff445d),
        9,
        glow: true,
      );
    }
    _gem(canvas, center, gemLane == 0 ? inner : outer, gemAngle);
  }

  void _orbitMarkers(Canvas canvas, Offset center, double inner, double outer) {
    final paint = Paint()
      ..color = const Color(0xff8cecff).withValues(alpha: .35)
      ..strokeWidth = 1;
    for (int i = 0; i < 12; i++) {
      final angle = i * _fullTurn / 12;
      final startRadius = inner - 2;
      final endRadius = i % 3 == 0 ? outer + 5 : inner + 2;
      canvas.drawLine(
        center +
            Offset(
              math.cos(angle) * startRadius,
              math.sin(angle) * startRadius,
            ),
        center +
            Offset(math.cos(angle) * endRadius, math.sin(angle) * endRadius),
        paint,
      );
    }
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
