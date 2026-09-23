import 'dart:math';

import 'package:flutter/material.dart';

import 'game.dart';

/// Two animation frames of the invader sprite, 11x8 pixels.
const _spriteFrames = [
  [
    '..X.....X..',
    '...X...X...',
    '..XXXXXXX..',
    '.XX.XXX.XX.',
    'XXXXXXXXXXX',
    'X.XXXXXXX.X',
    'X.X.....X.X',
    '...XX.XX...',
  ],
  [
    '..X.....X..',
    'X..X...X..X',
    'X.XXXXXXX.X',
    'XXX.XXX.XXX',
    'XXXXXXXXXXX',
    '.XXXXXXXXX.',
    '..X.....X..',
    '.X.......X.',
  ],
];

class _Star {
  _Star(this.x, this.y, this.size, this.speed);
  final double x, y, size, speed;
}

final List<_Star> _stars = () {
  final rnd = Random(7);
  return List.generate(
    90,
    (_) => _Star(
      rnd.nextDouble(),
      rnd.nextDouble(),
      0.6 + rnd.nextDouble() * 1.4,
      0.01 + rnd.nextDouble() * 0.04,
    ),
  );
}();

class GamePainter extends CustomPainter {
  GamePainter({
    required this.game,
    required this.clock,
    required this.heldMask,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Game game;

  /// Wall-clock seconds, used for background animation.
  final ValueGetter<double> clock;

  /// Colour currently being held on the buttons (0 if none).
  final ValueGetter<int> heldMask;

  @override
  void paint(Canvas canvas, Size size) {
    game.size = size;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintStars(canvas, size);
    _paintPulse(canvas);
    for (final m in game.monsters) {
      _paintMonster(canvas, m);
    }
    for (final e in game.explosions) {
      _paintExplosion(canvas, e);
    }
    _paintLauncher(canvas);
    _paintScore(canvas, size);
  }

  void _paintStars(Canvas canvas, Size size) {
    final t = clock();
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final s in _stars) {
      final y = (s.y + t * s.speed) % 1.0;
      canvas.drawCircle(
        Offset(s.x * size.width, y * size.height),
        s.size,
        paint,
      );
    }
  }

  void _paintMonster(Canvas canvas, Monster m) {
    final center = game.monsterPosition(m);
    final r = game.monsterRadius;
    final color = GameColors.of(m.mask);
    final frame = _spriteFrames[(m.age * 3).floor() % 2];
    final px = 2 * r / 11;
    final top = center.dy - px * 4;
    final left = center.dx - px * 5.5;

    // Soft glow so dark colours stay visible on black.
    canvas.drawCircle(
      center,
      r * 0.9,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final paint = Paint()..color = color;
    for (var row = 0; row < frame.length; row++) {
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

  void _paintPulse(Canvas canvas) {
    final p = game.pulse;
    if (p == null) return;
    final color = GameColors.of(p.mask);
    canvas.drawCircle(
      game.origin,
      p.radius,
      Paint()..color = color.withValues(alpha: 0.07),
    );
    canvas.drawCircle(
      game.origin,
      p.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      game.origin,
      p.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color,
    );
  }

  void _paintExplosion(Canvas canvas, Explosion e) {
    if (e.t < Explosion.burstDuration) _paintBurst(canvas, e);
    _paintPoints(canvas, e);
  }

  void _paintBurst(Canvas canvas, Explosion e) {
    final k = e.t / Explosion.burstDuration;
    final color = GameColors.of(e.mask).withValues(alpha: 1 - k);
    final paint = Paint()..color = color;
    final dist = game.monsterRadius * (0.3 + 2.2 * k);
    final s = game.monsterRadius * 0.25 * (1 - k * 0.6);
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6 + e.mask;
      final c = e.position + Offset(cos(a), sin(a)) * dist;
      canvas.drawRect(Rect.fromCenter(center: c, width: s, height: s), paint);
    }
  }

  /// "+N" rising from the explosion in the monster's colour, then fading.
  void _paintPoints(Canvas canvas, Explosion e) {
    final k = e.t / Explosion.duration;
    final rise = 1 - pow(1 - k, 3); // ease out
    final alpha = k < 0.6 ? 1.0 : 1 - (k - 0.6) / 0.4;
    final r = game.monsterRadius;
    final color = GameColors.of(e.mask);
    final tp = TextPainter(
      text: TextSpan(
        text: '+${GameColors.buttonsFor(e.mask)}',
        style: TextStyle(
          color: color.withValues(alpha: alpha),
          fontSize: r * (0.9 + 0.3 * min(k * 4, 1)),
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: alpha), blurRadius: 4),
            Shadow(color: color.withValues(alpha: alpha * 0.6), blurRadius: 12),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = e.position - Offset(0, r * 0.4 + r * 1.8 * rise);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Half-circle at the bottom centre showing the colour about to be fired.
  void _paintLauncher(Canvas canvas) {
    final held = heldMask();
    final ready = game.canFire;
    final color = held != 0
        ? GameColors.of(held)
        : Colors.white.withValues(alpha: ready ? 0.35 : 0.12);
    final r = game.monsterRadius * 0.9;
    final rect = Rect.fromCircle(center: game.origin, radius: r);
    canvas.drawArc(
      rect,
      pi,
      pi,
      true,
      Paint()..color = ready ? color : color.withValues(alpha: 0.3),
    );
  }

  void _paintScore(Canvas canvas, Size size) {
    if (game.phase == GamePhase.ready) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '${game.score}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(16, 12));
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
