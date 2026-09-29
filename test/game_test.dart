import 'dart:math';
import 'dart:ui';

import 'package:rgb_invaders/game/game.dart';
import 'package:flutter_test/flutter_test.dart';

Game _newGame() {
  final g = Game(random: Random(1))
    ..size = const Size(400, 800)
    ..start()
    ..spawning = false;
  return g;
}

Monster _monsterAt(Game g, int mask, double y) => Monster(
  mask: mask,
  baseX: 0.5,
  speed: 0,
  phase: 0, // no sway at age 0
)..y = y;

/// Fires at the boss's lowest band until it is gone.
void _beatBoss(Game g) {
  while (g.boss != null) {
    g.fire(g.boss!.target);
    g.update(0.05);
  }
}

/// Eight bands whose top and bottom colours differ.
const _bands = [1, 3, 2, 6, 4, 5, 7, 2];

Game _bossGame() {
  final g = _newGame();
  g.boss = Boss(bands: List.of(_bands), speed: 0, y: 0.1);
  return g;
}

void _runPulse(Game g) {
  for (var i = 0; i < 120 && g.pulse != null; i++) {
    g.update(1 / 60);
  }
}

void main() {
  test('only one circle at a time', () {
    final g = _newGame();
    expect(g.fire(GameColors.red), isTrue);
    expect(g.fire(GameColors.blue), isFalse);
    expect(g.pulse!.mask, GameColors.red);
  });

  test('circle destroys a monster of the same colour', () {
    final g = _newGame();
    final hits = <int>[];
    g.onHit = hits.add;
    g.monsters.add(_monsterAt(g, GameColors.red | GameColors.green, 0.5));
    g.fire(GameColors.red | GameColors.green);
    for (var i = 0; i < 60 && g.pulse != null; i++) {
      g.update(1 / 60);
    }
    expect(g.monsters, isEmpty);
    expect(g.score, 2); // yellow takes two buttons
    expect(g.pulse, isNull);
    expect(hits, [GameColors.red | GameColors.green]);
  });

  test('circle passes through other colours and ends at the top', () {
    final g = _newGame();
    var misses = 0;
    g.onMiss = () => misses++;
    g.monsters.add(_monsterAt(g, GameColors.blue, 0.5));
    g.fire(GameColors.red);
    var frames = 0;
    while (g.pulse != null && frames < 600) {
      g.update(1 / 60);
      g.monsters.first.age = 0; // keep it still
      g.monsters.first.y = 0.5;
      frames++;
    }
    expect(g.pulse, isNull);
    expect(g.monsters, hasLength(1));
    expect(g.score, 0);
    expect(g.canFire, isTrue);
    expect(misses, 1);
  });

  test('monster reaching the bottom ends the game', () {
    final g = _newGame();
    g.monsters.add(_monsterAt(g, GameColors.blue, 0.99));
    g.update(1 / 60);
    expect(g.phase, GamePhase.over);
    expect(g.canFire, isFalse);
  });

  test('monsters get faster and spawn more often', () {
    expect(Game.speedFor(25, 1), greaterThan(Game.speedFor(0, 1)));
    expect(Game.intervalFor(25, 1), lessThan(Game.intervalFor(0, 1)));
  });

  test('each wave opens with a slightly longer gap', () {
    expect(Game.intervalFor(0, 1), Game.startInterval);
    for (var w = 2; w <= Game.maxGroupSize; w++) {
      expect(Game.intervalFor(0, w), greaterThan(Game.intervalFor(0, w - 1)));
    }
    expect(Game.intervalFor(0, 20), Game.intervalFor(0, Game.maxGroupSize));
  });

  test('groups stop growing at five; later waves start faster', () {
    final g = Game(random: Random(4))
      ..size = const Size(400, 800)
      ..start()
      ..wave = 8;
    while (g.monsters.isEmpty) {
      g.update(0.05);
    }
    expect(g.monsters, hasLength(Game.maxGroupSize));
    expect(g.monsters.first.speed, Game.startSpeedFor(8));
    expect(Game.startSpeedFor(5), Game.startSpeed);
    expect(Game.startSpeedFor(6), greaterThan(Game.startSpeedFor(5)));
    expect(Game.startSpeedFor(7), greaterThan(Game.startSpeedFor(6)));
  });

  test('wave 1 ramps up fastest, easing off until wave 4', () {
    final speeds = [for (var w = 1; w <= 5; w++) Game.speedFor(25, w)];
    final gaps = [for (var w = 1; w <= 5; w++) Game.intervalFor(25, w)];
    for (var i = 1; i < 4; i++) {
      expect(speeds[i], lessThan(speeds[i - 1]));
      expect(gaps[i], greaterThan(gaps[i - 1]));
    }
    expect(speeds[4], speeds[3]); // wave 5 on ramps like wave 4
    expect(Game.speedFor(0, 4), Game.startSpeed);
  });

  test('points equal the buttons a colour needs', () {
    expect(GameColors.buttonsFor(GameColors.red), 1);
    expect(GameColors.buttonsFor(GameColors.green | GameColors.blue), 2);
    expect(GameColors.buttonsFor(7), 3);
  });

  test('after a wave of 25, speed resets and monsters come in pairs', () {
    final g = Game(random: Random(2))
      ..size = const Size(400, 800)
      ..start();
    final waves = <int>[];
    g.onWave = waves.add;
    // One entry per spawn: (group size, fall speed).
    final groups = <(int, double)>[];
    while (groups.length < Game.waveLength + 2) {
      g.update(0.05);
      if (g.boss != null) _beatBoss(g);
      if (g.monsters.isNotEmpty) {
        groups.add((g.monsters.length, g.monsters.first.speed));
        g.monsters.clear(); // keep the game from ending
      }
    }
    final first = groups.take(Game.waveLength);
    expect(first.every((s) => s.$1 == 1), isTrue);
    expect(first.last.$2, greaterThan(Game.startSpeed));
    expect(groups[Game.waveLength].$1, 2);
    expect(groups[Game.waveLength].$2, Game.startSpeed);
    expect(waves, [2]);
  });

  test('a group spawns side by side without overlapping', () {
    final g = Game(random: Random(5))
      ..size = const Size(400, 800)
      ..start()
      ..wave = 3;
    while (g.monsters.isEmpty) {
      g.update(0.05);
    }
    final xs = g.monsters.map((m) => m.baseX).toList();
    expect(xs, hasLength(3));
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i] - xs[i - 1], greaterThan(0.12));
    }
  });

  test('boss comes after the wave, once the field is clear', () {
    final g = Game(random: Random(3))
      ..size = const Size(400, 800)
      ..start();
    var bosses = 0;
    g.onBoss = () => bosses++;
    var spawns = 0;
    while (spawns < Game.waveLength) {
      g.update(0.05);
      if (g.monsters.isNotEmpty) spawns++;
      if (spawns < Game.waveLength) g.monsters.clear();
    }
    g.update(0.05);
    expect(g.boss, isNull, reason: 'monsters still on screen');
    g.monsters.clear();
    g.update(0.05);
    expect(g.boss, isNotNull);
    final bands = g.boss!.bands;
    expect(bands, hasLength(Boss.bandCount));
    expect(bands.every(GameColors.all.contains), isTrue);
    expect(bands.toSet(), GameColors.all.toSet());
    for (var i = 1; i < bands.length; i++) {
      expect(bands[i], isNot(bands[i - 1]));
    }
    expect(bosses, 1);
    // No new monsters while the boss is out.
    for (var i = 0; i < 100; i++) {
      g.update(0.05);
    }
    expect(g.monsters, isEmpty);
  });

  test('a new boss drops in quickly and the launcher waits for it', () {
    final g = _newGame();
    g.boss = Boss(
      bands: List.of(_bands),
      speed: Game.bossStartSpeed,
      y: -8 * g.bossPixel / g.size.height,
    );
    expect(g.canFire, isFalse);
    expect(g.fire(GameColors.red | GameColors.blue), isFalse);
    var t = 0.0;
    while (!g.canFire) {
      g.update(1 / 60);
      t += 1 / 60;
    }
    expect(t, lessThan(1.0));
    expect(g.boss!.y, Game.bossEntryY);
    expect(g.bossBandRect(g.boss!, 0).top, greaterThanOrEqualTo(0));
    // From then on it falls at its normal speed.
    for (var i = 0; i < 10; i++) {
      g.update(0.05);
    }
    expect(
      g.boss!.y,
      closeTo(Game.bossEntryY + 0.5 * Game.bossStartSpeed, 1e-9),
    );
  });

  test('only the lowest band of the boss can be hit', () {
    final g = _bossGame();
    var misses = 0;
    g.onMiss = () => misses++;
    final bands = g.boss!.bands;
    g.fire(bands.first); // top band: passes through
    _runPulse(g);
    expect(g.boss!.alive, bands.length);
    expect(misses, 1);

    g.fire(bands.last);
    _runPulse(g);
    expect(g.boss!.alive, bands.length - 1);
    expect(g.boss!.target, bands[bands.length - 2]);
    expect(g.score, GameColors.buttonsFor(bands.last));
  });

  test('a wrong colour pushes the boss down one row, once', () {
    final g = _bossGame();
    final b = g.boss!;
    final y0 = b.y;
    g.fire(b.bands.first); // not the lowest band
    _runPulse(g);
    for (var i = 0; i < 30; i++) {
      g.update(1 / 60);
    }
    expect(b.alive, b.bands.length);
    expect(b.push, 0);
    expect(b.y, closeTo(y0 + g.bossPixel / g.size.height, 1e-9));
  });

  test('shooting away every band beats the boss and starts a wave', () {
    final g = _bossGame();
    final waves = <int>[];
    g.onWave = waves.add;
    _beatBoss(g);
    final bandPoints = _bands.map(GameColors.buttonsFor);
    expect(g.score, bandPoints.reduce((a, b) => a + b) + Game.bossBonus);
    expect(g.wave, 2);
    expect(waves, [2]);
    expect(g.phase, GamePhase.playing);
  });

  test('boss ends the game when its lowest solid band hits the bottom', () {
    final g = _bossGame();
    final b = g.boss!;
    // With its three bottom bands gone the boss can sink further.
    b.alive = 5;
    // Band 4 (sprite row 4) ends 5 pixels below the top.
    b.y = (g.size.height - 5 * g.bossPixel) / g.size.height - 0.01;
    g.update(1 / 60);
    expect(g.phase, GamePhase.playing);
    b.y += 0.02;
    g.update(1 / 60);
    expect(g.phase, GamePhase.over);
  });

  group('turbo', () {
    /// Shoots one [mask] monster placed in the middle of the field.
    void kill(Game g, int mask) {
      g.monsters.add(_monsterAt(g, mask, 0.5));
      g.fire(mask);
      _runPulse(g);
    }

    test('five same-coloured kills in a row switch turbo on', () {
      final g = _newGame();
      var turbos = 0;
      g.onTurbo = () => turbos++;
      for (var i = 0; i < 4; i++) {
        kill(g, GameColors.red);
      }
      expect(g.streak, 4);
      expect(g.turbo, isFalse);
      kill(g, GameColors.red);
      expect(g.turbo, isTrue);
      expect(g.streak, 0);
      expect(turbos, 1);
    });

    test('another colour restarts the streak', () {
      final g = _newGame();
      for (var i = 0; i < 4; i++) {
        kill(g, GameColors.red);
      }
      kill(g, GameColors.blue);
      expect(g.streakMask, GameColors.blue);
      expect(g.streak, 1);
      expect(g.turbo, isFalse);
    });

    test('a circle that hits nothing ends the streak', () {
      final g = _newGame();
      for (var i = 0; i < 3; i++) {
        kill(g, GameColors.green);
      }
      g.fire(GameColors.green);
      _runPulse(g);
      expect(g.streak, 0);
    });

    test('a second streak in turbo clears the screen and scores it', () {
      final g = _newGame();
      final cleared = <Set<int>>[];
      g.onClear = cleared.add;
      for (var i = 0; i < 5; i++) {
        kill(g, GameColors.red);
      }
      for (var i = 0; i < 4; i++) {
        kill(g, GameColors.blue);
      }
      final before = g.score;
      g.monsters
        ..add(_monsterAt(g, GameColors.red | GameColors.green, 0.1))
        ..add(_monsterAt(g, 7, 0.15));
      kill(g, GameColors.blue);
      expect(g.monsters, isEmpty);
      expect(g.score, before + 1 + 2 + 3 + Game.turboBonus);
      expect(g.turbo, isFalse);
      expect(cleared, [
        {GameColors.red | GameColors.green, 7},
      ]);
    });

    test('turbo lasts through the boss into the next wave', () {
      final g = _bossGame()..turbo = true;
      _beatBoss(g);
      expect(g.boss, isNull);
      expect(g.wave, 2);
      expect(g.turbo, isTrue);
    });

    test('a turbo streak finished on the boss destroys it', () {
      final g = _bossGame()
        ..turbo = true
        ..streakMask = GameColors.green
        ..streak = 4;
      final waves = <int>[];
      g.onWave = waves.add;
      g.fire(GameColors.green); // the lowest band
      _runPulse(g);
      expect(g.boss, isNull);
      expect(g.turbo, isFalse);
      expect(waves, [2]);
      // Green band 1, the other seven bands 12, and both bonuses.
      expect(g.score, 1 + 12 + Game.bossBonus + Game.turboBonus);
    });
  });
}
