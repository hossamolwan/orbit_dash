import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const OrbitDashApp());

class OrbitDashApp extends StatelessWidget {
  const OrbitDashApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit Dash',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff070b18),
      colorScheme: const ColorScheme.dark(primary: Color(0xff55e7ff)),
    ),
    home: const OrbitGamePage(),
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

class OrbitGamePage extends StatefulWidget {
  const OrbitGamePage({super.key});

  @override
  State<OrbitGamePage> createState() => _OrbitGamePageState();
}

class _OrbitGamePageState extends State<OrbitGamePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
    _ticker = createTicker(_tick);
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _best = prefs.getInt('orbit_dash_best') ?? 0);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _state == RunState.playing) {
      _pause();
    }
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
      final speed = 1.55 + math.min(_score * 0.035, 1.5);
      _angle += speed * dt;
      _spawnClock += dt;
      if (_spawnClock > math.max(0.85, 2.0 - _score * 0.025)) {
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
  }

  void _finish() {
    _state = RunState.over;
    _ticker.stop();
    if (_score > _best) {
      _best = _score;
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt('orbit_dash_best', _best),
      );
    }
  }

  void _pause() {
    setState(() => _state = RunState.paused);
    _ticker.stop();
  }

  void _resume() {
    setState(() => _state = RunState.playing);
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _tapGame() {
    if (_state == RunState.playing) setState(() => _lane = 1 - _lane);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(
            constraints.maxWidth,
            constraints.maxHeight * 0.87,
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.blur_circular,
                      color: Color(0xff5ae8ff),
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'ORBIT DASH',
                      style: TextStyle(
                        letterSpacing: 3,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    _scorePill('BEST', '$_best'),
                    if (_state == RunState.playing) ...[
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
                child: Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _tapGame,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: Size.square(side),
                            painter: _OrbitPainter(
                              angle: _angle,
                              lane: _lane,
                              hazards: List.of(_hazards),
                              gemAngle: _gemAngle,
                              gemLane: _gemLane,
                            ),
                          ),
                          Positioned(
                            top: 22,
                            child: Column(
                              children: [
                                const Text(
                                  'SCORE',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    letterSpacing: 3,
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
                          if (_state != RunState.playing) _overlay(),
                        ],
                      ),
                    ),
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
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xe6101628),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x334fe7ff)),
        boxShadow: const [BoxShadow(color: Color(0x2200cfff), blurRadius: 30)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready
                ? Icons.auto_awesome
                : paused
                ? Icons.pause_circle_outline
                : Icons.brightness_3,
            color: ready ? const Color(0xff52e5ff) : const Color(0xffff5668),
            size: 34,
          ),
          const SizedBox(height: 13),
          Text(
            ready
                ? 'READY, PILOT?'
                : paused
                ? 'PAUSED'
                : 'RUN ENDED',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ready
                ? 'Dodge the red. Chase the glow.'
                : paused
                ? 'Your orbit is on hold.'
                : 'You collected $_score ${_score == 1 ? 'shard' : 'shards'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff9ca9c2),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (!ready && !paused) ...[
            const SizedBox(height: 14),
            Text(
              '$_score',
              style: const TextStyle(
                color: Color(0xff61e9ff),
                fontSize: 38,
                fontWeight: FontWeight.w300,
              ),
            ),
            Text(
              'BEST  $_best',
              style: const TextStyle(
                color: Color(0xff8491ab),
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: paused ? _resume : _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff54e6ff),
                foregroundColor: const Color(0xff06101d),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    paused
                        ? Icons.play_arrow_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ready
                        ? 'START RUN'
                        : paused
                        ? 'RESUME'
                        : 'PLAY AGAIN',
                    style: const TextStyle(
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hazard {
  _Hazard(this.angle, this.lane);
  double angle;
  final int lane;
  double relativeAngleTravel = 0;
}

class _OrbitPainter extends CustomPainter {
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
    for (int i = 0; i < 70; i++) {
      final x = (math.sin(i * 127.1) * 43758.5).abs() % size.width;
      final y = (math.sin(i * 71.7 + 2) * 11923.4).abs() % size.height;
      canvas.drawCircle(
        Offset(x, y),
        i % 9 == 0 ? 1.2 : .65,
        Paint()..color = Colors.white.withValues(alpha: .12 + (i % 5) * .025),
      );
    }
    for (final r in [inner, outer]) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = const Color(0xff50dff8).withValues(alpha: .10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = const Color(0xff5894c8).withValues(alpha: .4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    _planet(canvas, center, radius * .40);
    _orbitalThing(
      canvas,
      center,
      lane == 0 ? inner : outer,
      angle,
      const Color(0xff60efff),
      8,
      glow: true,
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

  void _planet(Canvas c, Offset center, double r) {
    c.drawCircle(
      center,
      r * 1.25,
      Paint()
        ..color = const Color(0xff455cff).withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
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
    for (int i = 0; i < 5; i++) {
      c.drawOval(
        Rect.fromCenter(
          center: center + Offset(-r * .2, (i - 2) * r * .33),
          width: r * 1.8,
          height: r * .12,
        ),
        Paint()..color = const Color(0xffc398ff).withValues(alpha: .08),
      );
    }
    c.restore();
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
  }) {
    final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
    if (glow)
      c.drawCircle(
        p,
        dot * 2,
        Paint()
          ..color = color.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
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
    c.drawCircle(
      p,
      14,
      Paint()
        ..color = color.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
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
