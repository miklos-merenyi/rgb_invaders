import 'package:rgb_invaders/game/chord_detector.dart';
import 'package:rgb_invaders/game/game.dart';
import 'package:flutter_test/flutter_test.dart';

// testWidgets runs in fake time, so tester.pump advances the chord timer.
void main() {
  late List<int> chords;
  late ChordDetector d;

  setUp(() {
    chords = [];
    d = ChordDetector(onChord: chords.add);
  });
  tearDown(() => d.dispose());

  testWidgets('single press fires its colour after the window', (t) async {
    d.down(1, GameColors.red);
    await t.pump(const Duration(milliseconds: 50));
    expect(chords, isEmpty);
    await t.pump(const Duration(milliseconds: 40));
    expect(chords, [GameColors.red]);
  });

  testWidgets('presses within the window combine', (t) async {
    d.down(1, GameColors.red);
    await t.pump(const Duration(milliseconds: 40));
    d.down(2, GameColors.blue);
    await t.pump(const Duration(milliseconds: 100));
    expect(chords, [GameColors.red | GameColors.blue]);
  });

  testWidgets('early release inside the window still counts', (t) async {
    d.down(1, GameColors.red);
    d.down(2, GameColors.green);
    await t.pump(const Duration(milliseconds: 20));
    d.up(1);
    await t.pump(const Duration(milliseconds: 100));
    expect(chords, [GameColors.red | GameColors.green]);
  });

  testWidgets('reset drops a pending chord', (t) async {
    d.down(1, GameColors.blue);
    d.reset();
    await t.pump(const Duration(milliseconds: 100));
    expect(chords, isEmpty);
    expect(d.held, 0);
  });
}
