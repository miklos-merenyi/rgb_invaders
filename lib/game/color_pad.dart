import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game.dart';

/// A glossy, domed colour button. Lights up in [litColor] (the colour of the
/// whole chord being held) while pressed.
class ColorPad extends StatelessWidget {
  const ColorPad({
    super.key,
    required this.mask,
    required this.pressed,
    required this.litColor,
    required this.ready,
  });

  final int mask;
  final bool pressed;
  final Color litColor;

  /// False while a circle is already on screen; the pad dims slightly.
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: pressed ? 1 : 0),
      duration: const Duration(milliseconds: 70),
      builder: (context, t, _) => AnimatedOpacity(
        opacity: ready || pressed ? 1 : 0.55,
        duration: const Duration(milliseconds: 120),
        child: CustomPaint(
          painter: _PadPainter(base: GameColors.of(mask), lit: litColor, t: t),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({required this.base, required this.lit, required this.t});

  final Color base;
  final Color lit;

  /// 0 = raised, 1 = fully pressed.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    const depth = 5.0;
    final press = depth * t;
    final face = Rect.fromLTWH(
      inset,
      inset + press,
      size.width - 2 * inset,
      size.height - 2 * inset - depth,
    );
    final radius = Radius.circular(face.shortestSide * 0.28);
    final faceRR = RRect.fromRectAndRadius(face, radius);
    final color = Color.lerp(base, lit, t)!;

    // Glow when lit.
    if (t > 0) {
      canvas.drawRRect(
        faceRR.inflate(4),
        Paint()
          ..color = color.withValues(alpha: 0.55 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
    }

    // Side of the key, visible below the face while raised.
    final side = RRect.fromRectAndRadius(
      Rect.fromLTWH(face.left, inset + depth, face.width, face.height),
      radius,
    );
    canvas.drawRRect(
      side.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      side,
      Paint()..color = Color.lerp(Colors.black, base, 0.3)!,
    );

    // Face: dome gradient peaking in the upper-middle.
    final peak = Offset(face.center.dx, face.top + face.height * 0.38);
    final dim = Color.lerp(Colors.black, color, 0.22 + 0.2 * t)!;
    final mid = Color.lerp(Colors.black, color, 0.6 + 0.35 * t)!;
    canvas.drawRRect(
      faceRR,
      Paint()..shader = ui.Gradient.radial(peak, face.width * 0.62, [mid, dim]),
    );

    canvas.save();
    canvas.clipRRect(faceRR);

    // Inner edge shadow gives the face some curvature.
    canvas.drawRRect(
      faceRR,
      Paint()
        ..shader = ui.Gradient.radial(
          peak,
          face.width * 0.75,
          [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
          [0.4, 1],
        ),
    );

    // Glossy highlight across the top.
    final gloss = Rect.fromLTWH(
      face.left + face.width * 0.1,
      face.top + face.height * 0.06,
      face.width * 0.8,
      face.height * 0.36,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gloss, Radius.circular(gloss.height / 2)),
      Paint()
        ..shader = ui.Gradient.linear(gloss.topCenter, gloss.bottomCenter, [
          Colors.white.withValues(alpha: 0.28 + 0.12 * t),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.restore();

    // Rim.
    canvas.drawRRect(
      faceRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Color.lerp(
          color,
          Colors.white,
          0.3,
        )!.withValues(alpha: 0.5 + 0.4 * t),
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.t != t || old.base != base || old.lit != lit;
}

/// Shows the four colour mixes under the buttons; the one being held lights up.
class MixLegend extends StatelessWidget {
  const MixLegend({super.key, required this.held});

  final int held;

  static const _mixes = [
    GameColors.red | GameColors.green,
    GameColors.red | GameColors.blue,
    GameColors.green | GameColors.blue,
    GameColors.red | GameColors.green | GameColors.blue,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          for (final mix in _mixes)
            Expanded(
              child: _MixChip(
                mix: mix,
                lit: held == mix,
                dim: held != 0 && held != mix,
              ),
            ),
        ],
      ),
    );
  }
}

class _MixChip extends StatelessWidget {
  const _MixChip({required this.mix, required this.lit, required this.dim});

  final int mix;
  final bool lit;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final result = GameColors.of(mix);
    final parts = [
      for (final c in const [GameColors.red, GameColors.green, GameColors.blue])
        if (mix & c != 0) c,
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 30,
      decoration: BoxDecoration(
        color: lit ? result.withValues(alpha: 0.18) : const Color(0xFF111118),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: lit ? result : Colors.white.withValues(alpha: 0.1),
          width: lit ? 1.5 : 1,
        ),
        boxShadow: lit
            ? [BoxShadow(color: result.withValues(alpha: 0.5), blurRadius: 12)]
            : null,
      ),
      child: AnimatedOpacity(
        opacity: dim ? 0.35 : 1,
        duration: const Duration(milliseconds: 100),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in parts) _dot(GameColors.of(p), 7),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                Icons.arrow_right_alt,
                size: 14,
                color: Colors.white54,
              ),
            ),
            _dot(result, 12, glow: true),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, double size, {bool glow = false}) => Container(
    width: size,
    height: size,
    margin: const EdgeInsets.symmetric(horizontal: 1.5),
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: glow
          ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)]
          : null,
    ),
  );
}
