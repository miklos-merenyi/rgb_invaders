import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_invaders/game/share_card.dart';

void main() {
  test('message counts beaten bosses and ends with the link', () {
    expect(
      shareMessage(score: 12, wave: 1),
      'I scored 12 in RGB Invaders! Can you beat it? $kShareUrl',
    );
    expect(shareMessage(score: 80, wave: 2), contains('and beat 1 boss!'));
    expect(shareMessage(score: 240, wave: 4), contains('and beat 3 bosses!'));
  });

  testWidgets('card renders as a 1080x1350 PNG', (tester) async {
    final png = await tester.runAsync(
      () => renderShareCard(score: 123, wave: 3),
    );
    final codec = await tester.runAsync(() => ui.instantiateImageCodec(png!));
    final frame = await tester.runAsync(() => codec!.getNextFrame());
    expect(frame!.image.width, 1080);
    expect(frame.image.height, 1350);
  });
}
