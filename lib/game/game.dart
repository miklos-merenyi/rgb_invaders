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

  /// Whether this circle, in the wrong colour, has already pushed the boss.
  bool pushedBoss = false;
}

/// The big banded invader that comes down between waves. Its bands are
/// shot away from the bottom up, and only the lowest remaining one can be
/// hit. Shot-away bands stay (see-through) and keep descending with it.
class Boss {
  Boss({required this.bands, required this.speed, required this.y});

  /// Sprite rows covered by each band, top to bottom, as (first row, count).
  static const List<(int, int)> bandRows = [
    (0, 2),
    (2, 1),
    (3, 1),
    (4, 1),
    (5, 1),
    (6, 2),
  ];

  /// Band colours in the order of the app icon, top to bottom.
  static const List<int> iconBands = [1, 3, 2, 6, 4, 5];

  /// Band colours, top to bottom, one per entry of [bandRows].
  final List<int> bands;

  /// Fall speed in play-field heights per second.
  final double speed;

  /// Top edge as a fraction of the play-field height.
  double y;

  /// Bands still solid: `bands[0]` to `bands[alive - 1]`.
  late int alive = bands.length;

  double age = 0;

  /// Distance still to be pushed down by wrong-coloured circles, as a
  /// fraction of the play-field height.
  double push = 0;

  /// The only colour that can hit the boss right now.
  int get target => bands[alive - 1];

  /// Which band a sprite row belongs to.
  static int bandOf(int row) => bandRows.lastIndexWhere((b) => b.$1 <= row);
}

class Explosion {
  Explosion(this.position, this.mask, {int? points})
    : points = points ?? GameColors.buttonsFor(mask);

  /// How long the particles fly.
  static const double burstDuration = 0.6;

  /// How long the "+N" points label floats (the explosion's total lifetime).
  static const double duration = 1.0;

  final Offset position;
  final int mask;

  /// Shown as "+N" rising from the explosion.
  final int points;
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
  Boss? boss;

  /// True from the last group of a wave until its boss appears.
  bool _bossPending = false;

  /// Bosses beaten this game; the first one wears the icon's colours.
  int _bossesBeaten = 0;

  /// Seconds since the current boss appeared (drives its banner).
  double bossTime = 0;

  int score = 0;
  int best = 0;
  int spawned = 0;
  double time = 0;
  double _spawnTimer = 0;

  /// Current wave (1-based). Wave n sends monsters in groups of n, up to
  /// [maxGroupSize].
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

  /// Called when a boss appears.
  void Function()? onBoss;

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
  // them in bigger groups (pairs, then threes, ...). Groups stop growing at
  // [maxGroupSize], which is as many as fit side by side on a phone; later
  // waves start faster instead.
  static const int waveLength = 25;
  static const int maxGroupSize = 5;

  /// Monsters per group in [wave].
  static int groupSizeFor(int wave) => min(wave, maxGroupSize);

  /// Pause between the last spawn of a wave and the first of the next.
  static const double waveBreak = 4.0;

  // Fall speed is in play-field heights per second (0.07 ≈ 14 s to fall).
  static const double startSpeed = 0.07;
  static const double lateWaveSpeedStep = 0.01; // per wave past maxGroupSize
  static const double speedStep = 0.0012; // added per monster
  static const double maxSpeed = 0.40;

  // Gap between monsters in seconds, shrinking by a factor per monster.
  // Each wave opens with a slightly longer gap than the one before while
  // its groups grow.
  static const double startInterval = 2.6;
  static const double startIntervalStep = 0.2;
  static const double intervalFactor = 0.990;
  static const double minInterval = 0.65;

  // How steeply a wave ramps up, as a multiple of [speedStep] and
  // [intervalFactor]: steep in wave 1, gentle from wave [lastRampWave] on
  // (its bigger groups are hard enough), linear in between.
  static const double firstRamp = 1.5;
  static const double lastRamp = 0.5;
  static const int lastRampWave = 4;

  static double rampFor(int wave) {
    final k = (wave - 1).clamp(0, lastRampWave - 1) / (lastRampWave - 1);
    return firstRamp + (lastRamp - firstRamp) * k;
  }

  /// Fall speed of the first group in [wave].
  static double startSpeedFor(int wave) =>
      startSpeed + max(0, wave - maxGroupSize) * lateWaveSpeedStep;

  /// Fall speed of the n-th group in [wave].
  static double speedFor(int n, int wave) =>
      min(startSpeedFor(wave) + n * speedStep * rampFor(wave), maxSpeed);

  /// Gap before the second group of [wave].
  static double startIntervalFor(int wave) =>
      startInterval + (groupSizeFor(wave) - 1) * startIntervalStep;

  /// Seconds until the group after the n-th one in [wave] appears.
  static double intervalFor(int n, int wave) => max(
    minInterval,
    startIntervalFor(wave) * pow(intervalFactor, n * rampFor(wave)),
  );

  // The boss after wave n falls a little faster than the one before.
  static const double bossStartSpeed = 0.035;
  static const double bossSpeedStep = 0.005;
  static const double bossMaxSpeed = 0.08;

  /// A new boss drops in at this speed until its top is at [bossEntryY];
  /// the launcher is locked until then.
  static const double bossEntrySpeed = 0.4;
  static const double bossEntryY = 0.02;

  /// A wrong-coloured circle reaching the boss pushes it down one sprite
  /// row, at this speed (play-field heights per second).
  static const double bossPushSpeed = 0.15;

  /// Extra points for shooting away a boss's last band.
  static const int bossBonus = 10;

  static double bossSpeedFor(int wave) =>
      min(bossStartSpeed + (wave - 1) * bossSpeedStep, bossMaxSpeed);

  /// Side of one sprite pixel of the boss, in logical pixels.
  double get bossPixel => min(size.width * 0.62 / 11, 30);

  Offset bossTopLeft(Boss b) {
    final sway = 0.05 * size.width * sin(b.age * 0.9);
    return Offset(size.width / 2 - bossPixel * 5.5 + sway, b.y * size.height);
  }

  /// The area covered by band [i] of the boss.
  Rect bossBandRect(Boss b, int i) {
    final px = bossPixel;
    final (row, rows) = Boss.bandRows[i];
    return bossTopLeft(b) + Offset(0, row * px) & Size(11 * px, rows * px);
  }

  /// True while a new boss is still dropping into view.
  bool get bossEntering {
    final b = boss;
    return b != null && b.y < bossEntryY;
  }

  bool get canFire =>
      phase == GamePhase.playing && pulse == null && !bossEntering;

  Offset monsterPosition(Monster m) {
    final sway = 0.04 * sin(m.age * 1.8 + m.phase);
    return Offset((m.baseX + sway) * size.width, m.y * size.height);
  }

  void start() {
    monsters.clear();
    explosions.clear();
    pulse = null;
    boss = null;
    _bossPending = false;
    _bossesBeaten = 0;
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

    bossTime += dt;

    if (_bossPending) {
      // The boss waits for the rest of its wave to be cleared.
      if (monsters.isEmpty) _spawnBoss();
    } else if (boss == null) {
      _spawnTimer -= dt;
      if (spawning && _spawnTimer <= 0) {
        _spawnGroup();
        _waveSpawns++;
        if (_waveSpawns >= waveLength) {
          _bossPending = true;
        } else {
          _spawnTimer = intervalFor(_waveSpawns, wave);
        }
      }
    }

    final b = boss;
    if (b != null) {
      b.age += dt;
      final push = min(b.push, bossPushSpeed * dt);
      b.push -= push;
      b.y = bossEntering
          ? min(b.y + bossEntrySpeed * dt, bossEntryY)
          : b.y + b.speed * dt + push;
      if (bossBandRect(b, b.alive - 1).bottom >= size.height) {
        _gameOver();
        return;
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

  /// Spawns a group of monsters side by side, each in its own lane. They
  /// share a sway phase so the group moves in formation and never overlaps.
  void _spawnGroup() {
    const margin = 0.12;
    final count = groupSizeFor(wave);
    final lane = (1 - 2 * margin) / count;
    final jitter = max(0.0, lane - 0.14);
    final phase = _random.nextDouble() * pi * 2;
    for (var i = 0; i < count; i++) {
      monsters.add(
        Monster(
          mask: GameColors.all[_random.nextInt(GameColors.all.length)],
          baseX:
              margin + lane * (i + 0.5) + (_random.nextDouble() - 0.5) * jitter,
          speed: speedFor(_waveSpawns, wave),
          phase: phase,
        )..y = -monsterRadius / size.height,
      );
      spawned++;
    }
  }

  void _spawnBoss() {
    _bossPending = false;
    final bands = List.of(Boss.iconBands);
    if (_bossesBeaten > 0) bands.shuffle(_random);
    boss = Boss(
      bands: bands,
      speed: bossSpeedFor(wave),
      y: -8 * bossPixel / size.height,
    );
    bossTime = 0;
    onBoss?.call();
  }

  /// Shoots away the boss's lowest band; the last one ends the boss and
  /// starts the next wave.
  void _hitBoss(Boss b) {
    final mask = b.target;
    final rect = bossBandRect(b, b.alive - 1);
    b.alive--;
    var points = GameColors.buttonsFor(mask);
    if (b.alive == 0) {
      points += bossBonus;
      boss = null;
      _bossesBeaten++;
      for (var i = 0; i < Boss.bandRows.length; i++) {
        explosions.add(
          Explosion(bossBandRect(b, i).center, b.bands[i], points: 0),
        );
      }
      wave++;
      _waveSpawns = 0;
      waveTime = 0;
      _spawnTimer = waveBreak;
      onWave?.call(wave);
    }
    explosions.add(Explosion(rect.center, mask, points: points));
    score += points;
    pulse = null;
    onHit?.call(mask);
  }

  /// Distance from the launcher to the nearest point of [rect].
  double _distanceTo(Rect rect) {
    final o = origin;
    final dx = max(0.0, max(rect.left - o.dx, o.dx - rect.right));
    final dy = max(0.0, max(rect.top - o.dy, o.dy - rect.bottom));
    return sqrt(dx * dx + dy * dy);
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

    final b = boss;
    final reachedBoss =
        b != null && p.radius >= _distanceTo(bossBandRect(b, b.alive - 1));
    if (hit == null && reachedBoss && b.target == p.mask) {
      _hitBoss(b);
    } else if (hit == null && reachedBoss && !p.pushedBoss) {
      // Wrong colour: it passes through, but the boss lurches closer.
      p.pushedBoss = true;
      b.push += bossPixel / size.height;
    } else if (hit != null) {
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
