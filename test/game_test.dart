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
    expect(Game.speedFor(30), greaterThan(Game.speedFor(0)));
    expect(Game.intervalFor(30), lessThan(Game.intervalFor(0)));
  });

  test('points equal the buttons a colour needs', () {
    expect(GameColors.buttonsFor(GameColors.red), 1);
    expect(GameColors.buttonsFor(GameColors.green | GameColors.blue), 2);
    expect(GameColors.buttonsFor(7), 3);
  });

  test('after a wave of 30, speed resets and monsters come in pairs', () {
    final g = Game(random: Random(2))
      ..size = const Size(400, 800)
      ..start();
    final waves = <int>[];
    g.onWave = waves.add;
    // One entry per spawn: (group size, fall speed).
    final groups = <(int, double)>[];
    while (groups.length < Game.waveLength + 2) {
      g.update(0.05);
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
}
