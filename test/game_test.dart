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

Game _bossGame() {
  final g = _newGame();
  g.boss = Boss(bands: List.of(Boss.iconBands), speed: 0, y: 0.1);
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
    expect(g.boss!.bands, Boss.iconBands);
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
      bands: List.of(Boss.iconBands),
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

  test('shooting away every band beats the boss and starts a wave', () {
    final g = _bossGame();
    final waves = <int>[];
    g.onWave = waves.add;
    _beatBoss(g);
    final bandPoints = Boss.iconBands.map(GameColors.buttonsFor);
    expect(g.score, bandPoints.reduce((a, b) => a + b) + Game.bossBonus);
    expect(g.wave, 2);
    expect(waves, [2]);
    expect(g.phase, GamePhase.playing);
  });

  test('boss ends the game when its lowest solid band hits the bottom', () {
    final g = _bossGame();
    final b = g.boss!;
    // With its two bottom bands gone the boss can sink further.
    b.alive = 4;
    // Band 3 (sprite row 4) ends 5 pixels below the top.
    b.y = (g.size.height - 5 * g.bossPixel) / g.size.height - 0.01;
    g.update(1 / 60);
    expect(g.phase, GamePhase.playing);
    b.y += 0.02;
    g.update(1 / 60);
    expect(g.phase, GamePhase.over);
  });
}
