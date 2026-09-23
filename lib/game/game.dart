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

  static const double duration = 0.6;

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

  /// Whether new monsters appear; tests turn this off.
  bool spawning = true;

  /// Called with the colour when a circle destroys a monster.
  void Function(int mask)? onHit;

  /// Called when a circle reaches the top without hitting anything.
  void Function()? onMiss;

  double get monsterRadius => min(size.width * 0.065, 30);

  Offset get origin => Offset(size.width / 2, size.height);

  /// Once the circle is this big it has covered the whole play-field.
  double get maxRadius =>
      sqrt(pow(size.width / 2, 2) + pow(size.height, 2)) + monsterRadius;

  /// Circle growth in pixels per second.
  double get pulseSpeed => size.height * 1.3;

  /// Fall speed (play-field heights per second) of the n-th monster.
  static double speedFor(int n) => min(0.07 + n * 0.0025, 0.40);

  /// Seconds until the monster after the n-th one appears.
  static double intervalFor(int n) => max(0.65, 2.6 * pow(0.975, n));

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
    _spawnTimer = 0.6;
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

    _spawnTimer -= dt;
    if (spawning && _spawnTimer <= 0) {
      _spawn();
      _spawnTimer = intervalFor(spawned);
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

  void _spawn() {
    final margin = 0.12;
    monsters.add(
      Monster(
        mask: GameColors.all[_random.nextInt(GameColors.all.length)],
        baseX: margin + _random.nextDouble() * (1 - 2 * margin),
        speed: speedFor(spawned),
        phase: _random.nextDouble() * pi * 2,
      )..y = -monsterRadius / size.height,
    );
    spawned++;
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
      score++;
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
