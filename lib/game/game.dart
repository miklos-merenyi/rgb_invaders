import 'dart:math';
import 'dart:ui';

/// Colours are RGB bit masks, so pressing several buttons simply ORs them.
class GameColors {
  static const int red = 1;
  static const int green = 2;
  static const int blue = 4;

  static const List<int> all = [1, 2, 3, 4, 5, 6, 7];

  /// Indexed by mask: none, R, G, R+G, B, R+B, G+B, R+G+B.
  static const List<Color> _palette = [
    Color(0xFF555555),
    Color(0xFFFF3B30), // red
    Color(0xFF34E03A), // green
    Color(0xFFFFEE33), // yellow
    Color(0xFF3D6BFF), // blue
    Color(0xFFFF3DF5), // magenta
    Color(0xFF33F0FF), // cyan
    Color(0xFFFFFFFF), // white
  ];

  static Color of(int mask) => _palette[mask & 7];

  /// How many buttons make this colour (1 for red, 2 for yellow, 3 for white).
  static int buttonsFor(int mask) =>
      (mask & 1) + (mask >> 1 & 1) + (mask >> 2 & 1);
}

enum GamePhase { ready, playing, over }

class Monster {
  Monster({
    required this.mask,
    required this.baseX,
    required this.speed,
    required this.phase,
  });

  final int mask;

  /// Horizontal centre as a fraction of the play-field width.
  final double baseX;

  /// Vertical centre as a fraction of the play-field height.
  double y = 0;

  /// Fall speed in play-field heights per second.
  final double speed;

  /// Random offset for the side-to-side sway.
  final double phase;

  double age = 0;
}

/// The expanding colour circle fired from the bottom centre.
class Pulse {
  Pulse(this.mask);

  final int mask;

  /// Radius in logical pixels.
  double radius = 0;
}

class Explosion {
  Explosion(this.position, this.mask);

  /// How long the particles fly.
  static const double burstDuration = 0.6;

  /// How long the "+N" points label floats (the explosion's total lifetime).
  static const double duration = 1.0;

  final Offset position;
  final int mask;
  double t = 0;

  bool get done => t >= duration;
}

class Game {
  Game({Random? random}) : _random = random ?? Random();

  final Random _random;

  Size size = Size.zero;
  GamePhase phase = GamePhase.ready;

  final List<Monster> monsters = [];
  final List<Explosion> explosions = [];
  Pulse? pulse;

  int score = 0;
  int best = 0;
  int spawned = 0;
  double time = 0;
  double _spawnTimer = 0;

  /// Current wave (1-based). Wave n sends monsters in groups of n.
  int wave = 1;

  /// Groups spawned so far in the current wave.
  int _waveSpawns = 0;

  /// Seconds since the current wave was announced (drives the banner).
  double waveTime = 0;

  /// Whether new monsters appear; tests turn this off.
  bool spawning = true;

  /// Called with the colour when a circle destroys a monster.
  void Function(int mask)? onHit;

  /// Called when a circle reaches the top without hitting anything.
  void Function()? onMiss;

  /// Called with the new wave number when a wave after the first begins.
  void Function(int wave)? onWave;

  double get monsterRadius => min(size.width * 0.065, 30);

  Offset get origin => Offset(size.width / 2, size.height);

  /// Once the circle is this big it has covered the whole play-field.
  double get maxRadius =>
      sqrt(pow(size.width / 2, 2) + pow(size.height, 2)) + monsterRadius;

  /// Circle growth in pixels per second.
  double get pulseSpeed => size.height * 1.3;

  // ── Difficulty tuning ──────────────────────────────────────────────────
  // The game runs in waves of [waveLength] spawns. Within a wave monsters
  // speed up and come more often; the next wave starts slow again but sends
  // them in bigger groups (pairs, then threes, ...).
  static const int waveLength = 30;

  /// Pause between the last spawn of a wave and the first of the next.
  static const double waveBreak = 4.0;

  // Fall speed is in play-field heights per second (0.07 ≈ 14 s to fall).
  static const double startSpeed = 0.07;
  static const double speedStep = 0.0012; // added per monster
  static const double maxSpeed = 0.40;

  // Gap between monsters in seconds, shrinking by a factor per monster.
  static const double startInterval = 2.6;
  static const double intervalFactor = 0.990;
  static const double minInterval = 0.65;

  /// Fall speed of the n-th group in a wave.
  static double speedFor(int n) => min(startSpeed + n * speedStep, maxSpeed);

  /// Seconds until the group after the n-th one in a wave appears.
  static double intervalFor(int n) =>
      max(minInterval, startInterval * pow(intervalFactor, n));

  bool get canFire => phase == GamePhase.playing && pulse == null;

  Offset monsterPosition(Monster m) {
    final sway = 0.04 * sin(m.age * 1.8 + m.phase);
    return Offset((m.baseX + sway) * size.width, m.y * size.height);
  }

  void start() {
    monsters.clear();
    explosions.clear();
    pulse = null;
    score = 0;
    spawned = 0;
    time = 0;
    wave = 1;
    _waveSpawns = 0;
    waveTime = 0;
    _spawnTimer = 1.2;
    phase = GamePhase.playing;
  }

  /// Fires a circle of [mask] colour. Returns false if one is already active.
  bool fire(int mask) {
    if (!canFire || mask == 0) return false;
    pulse = Pulse(mask);
    return true;
  }

  void update(double dt) {
    if (size.isEmpty) return;
    dt = min(dt, 0.05);

    for (final e in explosions) {
      e.t += dt;
    }
    explosions.removeWhere((e) => e.done);

    if (phase != GamePhase.playing) return;
    time += dt;
    waveTime += dt;

    _spawnTimer -= dt;
    if (spawning && _spawnTimer <= 0) {
      _spawnGroup();
      _waveSpawns++;
      if (_waveSpawns >= waveLength) {
        wave++;
        _waveSpawns = 0;
        waveTime = 0;
        _spawnTimer = waveBreak;
        onWave?.call(wave);
      } else {
        _spawnTimer = intervalFor(_waveSpawns);
      }
    }

    final r = monsterRadius;
    for (final m in monsters) {
      m.age += dt;
      m.y += m.speed * dt;
      if (m.y * size.height + r >= size.height) {
        _gameOver();
        return;
      }
    }

    _updatePulse(dt);
  }

  /// Spawns [wave] monsters side by side, each in its own lane. They share
  /// a sway phase so the group moves in formation and never overlaps.
  void _spawnGroup() {
    const margin = 0.12;
    final lane = (1 - 2 * margin) / wave;
    final jitter = max(0.0, lane - 0.14);
    final phase = _random.nextDouble() * pi * 2;
    for (var i = 0; i < wave; i++) {
      monsters.add(
        Monster(
          mask: GameColors.all[_random.nextInt(GameColors.all.length)],
          baseX:
              margin + lane * (i + 0.5) + (_random.nextDouble() - 0.5) * jitter,
          speed: speedFor(_waveSpawns),
          phase: phase,
        )..y = -monsterRadius / size.height,
      );
      spawned++;
    }
  }

  void _updatePulse(double dt) {
    final p = pulse;
    if (p == null) return;
    p.radius += pulseSpeed * dt;

    // The circle's edge touches a monster when the monster's centre is within
    // one monster-radius of the ring. Pick the closest matching one.
    final r = monsterRadius;
    Monster? hit;
    var hitDist = double.infinity;
    for (final m in monsters) {
      if (m.mask != p.mask) continue;
      final d = (monsterPosition(m) - origin).distance;
      if ((d - p.radius).abs() <= r && d < hitDist) {
        hit = m;
        hitDist = d;
      }
    }

    if (hit != null) {
      explosions.add(Explosion(monsterPosition(hit), hit.mask));
      monsters.remove(hit);
      score += GameColors.buttonsFor(hit.mask);
      pulse = null;
      onHit?.call(hit.mask);
    } else if (p.radius > maxRadius) {
      pulse = null;
      onMiss?.call();
    }
  }

  void _gameOver() {
    phase = GamePhase.over;
    pulse = null;
    best = max(best, score);
  }
}
