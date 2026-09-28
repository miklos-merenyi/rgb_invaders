import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'game.dart';
import 'game_painter.dart';

/// Where the QR code and the share message send people: the page picks the
/// right store for their phone.
const kShareUrl = 'https://miklos-merenyi.github.io/rgb_invaders/get.html';

/// The share card's size: 4:5, which Instagram and most chats show uncropped.
const kShareCardSize = Size(1080, 1350);

/// The text shared alongside the card.
String shareMessage({required int score, required int wave}) {
  final bosses = wave - 1;
  final reached = bosses == 0
      ? ''
      : ' and beat $bosses boss${bosses == 1 ? '' : 'es'}';
  return 'I scored $score in RGB Invaders$reached! Can you beat it? '
      '$kShareUrl';
}

/// The share card as a PNG.
Future<Uint8List> renderShareCard({
  required int score,
  required int wave,
}) async {
  final recorder = ui.PictureRecorder();
  paintShareCard(Canvas(recorder), score: score, wave: wave);
  final image = await recorder.endRecording().toImage(
    kShareCardSize.width.toInt(),
    kShareCardSize.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

// Same as the app icon (tool/make_icons.py).
const _bgCenter = Color(0xFF241652);
const _bgEdge = Color(0xFF050412);

/// Sprite row -> colour, as on the app icon: antennae red, then one band per
/// row, feet magenta.
const _iconRowColors = [1, 1, 3, 2, 6, 4, 5, 5];

/// "RGB" in its own colours, then "INVADERS" in the icon's rainbow, as on
/// the start screen.
const _titleColors = [
  GameColors.red,
  GameColors.green,
  GameColors.blue,
  ...GameColors.rainbow,
];

/// Draws the card: the icon's invader and the title, the score, how far
/// the player got, and a QR code to the game.
void paintShareCard(Canvas canvas, {required int score, required int wave}) {
  final size = kShareCardSize;
  final w = size.width;

  // Space background with fixed stars, so every card looks the same.
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, size.height * 0.3),
        size.height * 0.75,
        [_bgCenter, _bgEdge],
      ),
  );
  final random = Random(7);
  final star = Paint()..color = Colors.white;
  for (var i = 0; i < 90; i++) {
    star.color = Colors.white.withValues(
      alpha: 0.2 + random.nextDouble() * 0.5,
    );
    canvas.drawCircle(
      Offset(random.nextDouble() * w, random.nextDouble() * size.height),
      1 + random.nextDouble() * 2,
      star,
    );
  }

  _paintInvader(canvas, Offset(w / 2, 150), 20);

  var y = 265.0;
  y += _paintText(canvas, _rainbowSpan('RGB INVADERS', 84, _titleColors), y);

  y += 40;
  y += _paintText(canvas, _plain('I scored', 44, Colors.white70), y);
  y += _paintText(
    canvas,
    _plain('$score', 180, Colors.white, weight: FontWeight.w900),
    y - 10,
  );
  final bosses = wave - 1;
  final progress = bosses == 0
      ? 'Wave $wave'
      : 'Wave $wave  ·  $bosses boss${bosses == 1 ? '' : 'es'} beaten';
  y += _paintText(canvas, _plain(progress, 40, Colors.white60), y);

  // QR code on a white tile, which scanners need for contrast.
  const tile = 380.0;
  const pad = 26.0;
  final tileRect = Rect.fromLTWH((w - tile) / 2, y + 50, tile, tile);
  canvas.drawRRect(
    RRect.fromRectAndRadius(tileRect.inflate(4), const Radius.circular(36)),
    Paint()
      ..color = GameColors.of(GameColors.all.last).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(tileRect, const Radius.circular(32)),
    Paint()..color = Colors.white,
  );
  canvas.save();
  canvas.translate(tileRect.left + pad, tileRect.top + pad);
  QrPainter(
    data: kShareUrl,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF12121E),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF12121E),
    ),
  ).paint(canvas, const Size.square(tile - 2 * pad));
  canvas.restore();

  _paintText(
    canvas,
    _plain('Can you beat it? Scan to play', 40, Colors.white),
    tileRect.bottom + 40,
  );
}

/// The icon's invader, centred on [center], with sprite pixels of side [px].
void _paintInvader(Canvas canvas, Offset center, double px) {
  final frame = invaderFrames.first;
  final left = center.dx - px * frame.first.length / 2;
  final top = center.dy - px * frame.length / 2;
  canvas.drawCircle(
    center,
    px * 6,
    Paint()
      ..color = GameColors.of(GameColors.blue).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
  );
  for (var row = 0; row < frame.length; row++) {
    final paint = Paint()..color = GameColors.of(_iconRowColors[row]);
    final line = frame[row];
    for (var col = 0; col < line.length; col++) {
      if (line.codeUnitAt(col) != 0x58) continue; // 'X'
      canvas.drawRect(
        Rect.fromLTWH(left + col * px, top + row * px, px + 0.5, px + 0.5),
        paint,
      );
    }
  }
}

/// Paints [span] centred horizontally with its top at [y]; returns its height.
double _paintText(Canvas canvas, TextSpan span, double y) {
  final painter = TextPainter(
    text: span,
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: kShareCardSize.width - 80);
  painter.paint(canvas, Offset((kShareCardSize.width - painter.width) / 2, y));
  final height = painter.height;
  painter.dispose();
  return height;
}

TextSpan _plain(
  String text,
  double fontSize,
  Color color, {
  FontWeight weight = FontWeight.w600,
}) => TextSpan(
  text: text,
  style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
);

/// [text] with each letter in the next of [colors], glowing in its colour.
TextSpan _rainbowSpan(String text, double fontSize, List<int> colors) {
  final base = TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w900,
    letterSpacing: 6,
  );
  final letters = <TextSpan>[];
  var i = 0;
  for (final ch in text.split('')) {
    if (ch == ' ') {
      letters.add(TextSpan(text: ch, style: base));
      continue;
    }
    final color = GameColors.of(colors[i++ % colors.length]);
    letters.add(
      TextSpan(
        text: ch,
        style: base.copyWith(
          color: color,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.7), blurRadius: 24),
          ],
        ),
      ),
    );
  }
  return TextSpan(children: letters);
}
