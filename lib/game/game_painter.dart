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
    // Shot-away boss bands keep falling past the bottom edge.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintStars(canvas, size);
    _paintPulse(canvas);
    for (final m in game.monsters) {
      _paintMonster(canvas, m);
    }
    final boss = game.boss;
    if (boss != null) _paintBoss(canvas, boss);
    for (final e in game.explosions) {
      _paintExplosion(canvas, e);
    }
    _paintLauncher(canvas);
    _paintScore(canvas, size);
    _paintWaveBanner(canvas, size);
    _paintBossBanner(canvas, size);
  }

  static const _bannerDuration = 2.6;

  /// "WAVE n" with the group size, fading in and out as a wave begins.
  void _paintWaveBanner(Canvas canvas, Size size) {
    final n = game.wave;
    final subtitle = n > Game.maxGroupSize
        ? 'faster!'
        : switch (n) {
            1 => null,
            2 => 'in pairs!',
            3 => 'in threes!',
            4 => 'in fours!',
            _ => '$n at a time!',
          };
    _paintBanner(canvas, size, game.waveTime, 'WAVE $n', subtitle);
  }

  void _paintBossBanner(Canvas canvas, Size size) {
    if (game.boss == null) return;
    _paintBanner(canvas, size, game.bossTime, 'BOSS', 'hit its lowest colour!');
  }

  /// A title fading in and out over [_bannerDuration] seconds from [t] = 0.
  void _paintBanner(
    Canvas canvas,
    Size size,
    double t,
    String title,
    String? subtitle,
  ) {
    if (game.phase != GamePhase.playing) return;
    if (t >= _bannerDuration) return;
    final alpha = min(1.0, min(t / 0.3, (_bannerDuration - t) / 0.6));
    final tp = TextPainter(
      textAlign: TextAlign.center,
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: alpha),
          fontSize: 40,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
        children: [
          if (subtitle != null)
            TextSpan(
              text: '\n$subtitle',
              style: TextStyle(
                color: Colors.white70.withValues(alpha: 0.7 * alpha),
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, size.height * 0.4 - tp.height / 2),
    );
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

  /// The boss in its colour bands. Shot-away bands are drawn see-through,
  /// and the one that can be hit now pulses.
  void _paintBoss(Canvas canvas, Boss b) {
    final px = game.bossPixel;
    final topLeft = game.bossTopLeft(b);
    final frame = _spriteFrames[(b.age * 1.5).floor() % 2];
    final targetGlow = 0.35 + 0.25 * sin(clock() * 8);

    for (var i = 0; i < b.alive; i++) {
      final rect = game.bossBandRect(b, i);
      final isTarget = i == b.alive - 1;
      canvas.drawRect(
        rect.inflate(px * 0.3),
        Paint()
          ..color = GameColors.of(
            b.bands[i],
          ).withValues(alpha: isTarget ? targetGlow : 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.8),
      );
    }

    for (var row = 0; row < frame.length; row++) {
      final band = Boss.bandOf(row);
      final solid = band < b.alive;
      final paint = Paint()
        ..color = GameColors.of(
          b.bands[band],
        ).withValues(alpha: solid ? 1 : 0.2);
      final line = frame[row];
      for (var col = 0; col < line.length; col++) {
        if (line.codeUnitAt(col) != 0x58) continue; // 'X'
        canvas.drawRect(
          Rect.fromLTWH(
            topLeft.dx + col * px,
            topLeft.dy + row * px,
            px + 0.5,
            px + 0.5,
          ),
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
    if (e.points > 0) _paintPoints(canvas, e);
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
        text: '+${e.points}',
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

  /// Half-circle at the bottom centre showing the colour about to be fired,
  /// or the colour of the circle still out.
  void _paintLauncher(Canvas canvas) {
    final pulse = game.pulse;
    final held = heldMask();
    final ready = game.canFire;
    final color = pulse != null
        ? GameColors.of(pulse.mask)
        : held != 0
        ? GameColors.of(held)
        : Colors.white.withValues(alpha: ready ? 0.35 : 0.12);
    final r = game.monsterRadius * 0.9;
    final rect = Rect.fromCircle(center: game.origin, radius: r);
    canvas.drawArc(
      rect,
      pi,
      pi,
      true,
      Paint()
        ..color = ready || pulse != null ? color : color.withValues(alpha: 0.3),
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
