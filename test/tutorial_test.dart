import 'dart:ui';

import 'package:flutter/material.dart' hide Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_invaders/game/game.dart';
import 'package:rgb_invaders/game/game_screen.dart';
import 'package:rgb_invaders/game/tutorial.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shoots everything on the field in its own colour.
void _clearField(Game g) {
  for (var i = 0; i < 400 && (g.monsters.isNotEmpty || g.boss != null); i++) {
    final target = g.boss?.target ?? g.monsters.first.mask;
    g.fire(target);
    g.update(0.05);
  }
}

void main() {
  group('practice', () {
    test('an invader reaching the bottom goes back to the top', () {
      final g = Game()
        ..size = const Size(400, 800)
        ..startPractice()
        ..dropMonster(GameColors.red);
      g.monsters.first.y = 0.99;
      g.update(0.016);
      expect(g.phase, GamePhase.playing);
      expect(g.monsters.single.y, lessThan(0));
    });

    test('a boss reaching the bottom goes back to the top', () {
      final g = Game()
        ..size = const Size(400, 800)
        ..startPractice();
      g.dropBoss(const [5, 2, 7, 3, 6, 1, 4, 3]).y = 0.95;
      g.update(0.016);
      expect(g.phase, GamePhase.playing);
      expect(g.boss!.y, Game.bossEntryY);
    });

    test('one ring destroys only one of two same-coloured invaders', () {
      final g = Game()
        ..size = const Size(400, 800)
        ..startPractice()
        ..dropMonster(GameColors.green, x: 0.3)
        ..dropMonster(GameColors.green, x: 0.7);
      for (final m in g.monsters) {
        m.y = 0.4;
      }
      expect(g.fire(GameColors.green), isTrue);
      while (g.pulse != null) {
        g.update(0.016);
      }
      expect(g.monsters, hasLength(1));
    });

    test('nothing spawns but what is dropped in', () {
      final g = Game()
        ..size = const Size(400, 800)
        ..startPractice();
      for (var i = 0; i < 200; i++) {
        g.update(0.05);
      }
      expect(g.monsters, isEmpty);
      expect(g.boss, isNull);
    });

    test('a real game after practice ends at the bottom again', () {
      final g = Game()
        ..size = const Size(400, 800)
        ..startPractice()
        ..start()
        ..spawning = false
        ..dropMonster(GameColors.red);
      g.monsters.first.y = 0.99;
      g.update(0.016);
      expect(g.phase, GamePhase.over);
    });
  });

  test('the tutorial moves through every step to the closing card', () {
    final g = Game()..size = const Size(400, 800);
    final tutorial = Tutorial(g)..begin();
    for (var i = 0; i < Tutorial.steps.length - 1; i++) {
      expect(tutorial.finished, isFalse);
      _clearField(g);
      for (var t = 0.0; tutorial.step == i; t += 0.1) {
        tutorial.update(0.1);
        expect(t, lessThan(Tutorial.praisePause + 1));
      }
    }
    expect(tutorial.finished, isTrue);
    expect(g.phase, GamePhase.playing);
    expect(g.best, 0);
  });

  test('the boss step ends after three bands with praise', () {
    final g = Game()..size = const Size(400, 800);
    final tutorial = Tutorial(g)..begin();
    while (g.boss == null) {
      _clearField(g);
      tutorial.update(Tutorial.stepPause);
      tutorial.update(Tutorial.stepPause);
    }
    for (var shot = 0; g.boss!.alive > Boss.bandCount - Tutorial.bossBands;) {
      if (g.fire(g.boss!.target)) shot++;
      g.update(0.05);
      expect(shot, lessThan(50));
    }
    expect(tutorial.update(0.016), isTrue);
    expect(g.boss, isNull);
    expect(tutorial.text, "You've got it!");
    expect(tutorial.update(Tutorial.praisePause / 2), isFalse);
    expect(tutorial.update(Tutorial.praisePause), isTrue);
    expect(tutorial.finished, isTrue);
  });

  testWidgets('the tutorial opens from the start screen and can be skipped', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final game = Game();
    await t.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Tutorial'));
    await t.pump(const Duration(milliseconds: 16));
    expect(game.practice, isTrue);
    expect(find.textContaining('to fire a ring'), findsOneWidget);
    expect(find.text('Start Game'), findsNothing);

    await t.tap(find.text('Skip tutorial'));
    await t.pump(const Duration(milliseconds: 16));
    expect(game.phase, GamePhase.ready);
    expect(find.text('Start Game'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the instructions open from the start screen', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(MaterialApp(home: GameScreen(game: Game())));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Instructions'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('How to play'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('How to play'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
