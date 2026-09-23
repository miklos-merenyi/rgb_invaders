import 'package:circles/game/color_pad.dart';
import 'package:circles/game/game.dart';
import 'package:circles/game/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('two fingers on red and blue fire a magenta circle', (t) async {
    final game = Game()..spawning = false;
    await t.pumpWidget(MaterialApp(home: GameScreen(game: game)));
    await t.pump(const Duration(milliseconds: 16));
    await t.tap(find.text('Tap to play'));
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
}
