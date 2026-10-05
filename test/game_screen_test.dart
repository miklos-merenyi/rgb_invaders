import 'package:rgb_invaders/game/color_pad.dart';
import 'package:rgb_invaders/game/game.dart';
import 'package:rgb_invaders/game/game_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('two fingers on red and blue fire a magenta circle', (t) async {
    final game = Game()..spawning = false;
    await t.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Start Game'));
    game.spawning = false;
    await t.pump(const Duration(milliseconds: 16));

    final buttons = find.byType(ColorPad);
    final red = await t.startGesture(t.getCenter(buttons.at(0)), pointer: 1);
    await t.pump(const Duration(milliseconds: 30));
    final blue = await t.startGesture(t.getCenter(buttons.at(2)), pointer: 2);
    await t.pump(const Duration(milliseconds: 100));

    expect(game.pulse?.mask, GameColors.red | GameColors.blue);
    await red.up();
    await blue.up();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('J and K pressed together fire a yellow circle', (t) async {
    final game = Game()..spawning = false;
    await t.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Start Game'));
    game.spawning = false;
    await t.pump(const Duration(milliseconds: 16));

    await t.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await t.pump(const Duration(milliseconds: 30));
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await t.pump(const Duration(milliseconds: 100));

    expect(game.pulse?.mask, GameColors.red | GameColors.green);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the Mac app shows each pad\'s key', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await t.pumpWidget(const MaterialApp(home: GameScreen()));
    await t.pump(const Duration(milliseconds: 16));
    for (final key in ['J', 'K', 'L']) {
      expect(
        find.descendant(of: find.byType(ColorPad), matching: find.text(key)),
        findsOneWidget,
      );
    }
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('game-over screen appears only after the post-game pause', (
    t,
  ) async {
    final game = Game()..spawning = false;
    await t.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Start Game'));
    game.spawning = false;
    game.monsters.add(
      Monster(mask: GameColors.red, baseX: 0.5, speed: 0, phase: 0)..y = 1,
    );
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    expect(game.phase, GamePhase.over);
    expect(find.text('GAME OVER'), findsNothing);

    await t.pump(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 16));
    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.textContaining('remove ads'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
