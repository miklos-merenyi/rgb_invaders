import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game.dart';

/// Two animation frames of the primary-colour invader (also the icon), 11x8
/// pixels.
const invaderFrames = [
  [
    '...XXXXX...',
    '.XXXXXXXXX.',
    'XXXX...XXXX',
    'XXXX.X.XXXX',
    'XXXX...XXXX',
    'XXXXXXXXXXX',
    'X.X.X.X.X.X',
    '.X.X.X.X.X.',
  ],
  [
    '...XXXXX...',
    '.XXXXXXXXX.',
    'XXXX...XXXX',
    'XXXX.X.XXXX',
    'XXXX...XXXX',
    'XXXXXXXXXXX',
    '.X.X.X.X.X.',
    'X.X.X.X.X.X',
  ],
];

/// The mixed-colour (two-button) invader, a bat twitching its wing tips and
/// feet. Every row has pixels in both frames, since each row is a boss band.
const batFrames = [
  [
    'X.........X',
    'XX..X.X..XX',
    'XXX.XXX.XXX',
    'XXXXXXXXXXX',
    '.XXX.X.XXX.',
    '..XXXXXXX..',
    '...X.X.X...',
    '..X.....X..',
  ],
  [
    '.X.......X.',
    'XX..X.X..XX',
    'XXX.XXX.XXX',
    'XXXXXXXXXXX',
    '.XXX.X.XXX.',
    '..XXXXXXX..',
    '...X.X.X...',
    '...X...X...',
  ],
];

/// The white (three-button) invader, a spiky urchin whose spikes pulse.
const urchinFrames = [
  [
    '.....X.....',
    '.X..XXX..X.',
    '..XXXXXXX..',
    '.XXX.X.XXX.',
    'XXXXXXXXXXX',
    '.XXX...XXX.',
    '..XXXXXXX..',
    '.X..XXX..X.',
  ],
  [
    'X....X....X',
    '..X.XXX.X..',
    '..XXXXXXX..',
    'XXXX.X.XXXX',
    '.XXXXXXXXX.',
    'XXXX...XXXX',
    '..XXXXXXX..',
    'X...XXX...X',
  ],
];

/// The three invader sprites, by how many buttons make their colour (minus
/// one). Also indexed by [Boss.shape].
const shapeFrames = [invaderFrames, batFrames, urchinFrames];

/// The sprite for an invader of colour [mask].
List<List<String>> framesFor(int mask) =>
    shapeFrames[GameColors.buttonsFor(mask) - 1];

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
    canvas.save();
    _shakeForClear(canvas);
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
    _paintClearWave(canvas, size);
    canvas.restore();
    _paintLauncher(canvas);
    _paintScore(canvas, size);
    _paintStreak(canvas);
    _paintWaveBanner(canvas, size);
    _paintBossBanner(canvas, size);
    _paintTurboBanners(canvas, size);
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

  void _paintTurboBanners(Canvas canvas, Size size) {
    _paintBanner(
      canvas,
      size,
      game.turboTime,
      'TURBO!',
      '${Game.streakLength} in a row clears the screen!',
    );
    _paintBanner(
      canvas,
      size,
      game.clearTime,
      'CLEAR!',
      '+${Game.turboBonus} bonus!',
    );
  }

  static const _clearShake = 0.4;
  static const _clearWaveDuration = 0.7;

  /// Jolts the play-field for a moment after a turbo clear, dying away.
  void _shakeForClear(Canvas canvas) {
    final t = game.clearTime;
    if (t >= _clearShake) return;
    final k = 10 * (1 - t / _clearShake);
    canvas.translate(sin(t * 90) * k, cos(t * 77) * k);
  }

  /// A white flash and three rainbow shockwaves sweeping out from the
  /// launcher across the whole screen after a turbo clear.
  void _paintClearWave(Canvas canvas, Size size) {
    final t = game.clearTime;
    if (t < 0.2) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.5 * (1 - t / 0.2)),
      );
    }
    final rainbow = [
      for (final m in GameColors.rainbow) GameColors.of(m),
      GameColors.of(GameColors.rainbow.first),
    ];
    for (var i = 0; i < 3; i++) {
      final k = (t - i * 0.12) / _clearWaveDuration;
      if (k < 0 || k >= 1) continue;
      final radius = game.maxRadius * (1 - pow(1 - k, 2));
      final rect = Rect.fromCircle(center: game.origin, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18 * (1 - k) + 4
        ..shader = SweepGradient(
          colors: [for (final c in rainbow) c.withValues(alpha: (1 - k) * 0.9)],
          transform: GradientRotation(t * 6 + i),
        ).createShader(rect);
      // Triangles, not a stroked circle; see [_ring].
      canvas.drawVertices(
        _ring(game.origin, radius, paint.strokeWidth),
        BlendMode.srcOver,
        paint,
      );
    }
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
    final frame = framesFor(m.mask)[(m.age * 3).floor() % 2];
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
    final frame = shapeFrames[b.shape][(b.age * 1.5).floor() % 2];
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
      final solid = row < b.alive;
      final paint = Paint()
        ..color = GameColors.of(
          b.bands[row],
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
    canvas.drawPath(
      Path()..addOval(Rect.fromCircle(center: game.origin, radius: p.radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawVertices(
      _ring(game.origin, p.radius, 4),
      BlendMode.srcOver,
      Paint()..color = color,
    );
  }

  /// A ring of [width] around [radius], as a strip of triangles.
  ///
  /// Not a stroked circle or oval path: Impeller draws those with a
  /// per-pixel distance that overflows on low-precision GPUs, so big rings
  /// lose their sharp edge or vanish (seen on a Moto G50 and a Lenovo Tab
  /// M10). Plain triangles look the same on every GPU.
  static ui.Vertices _ring(Offset center, double radius, double width) {
    final inner = max(0.0, radius - width / 2);
    final outer = radius + width / 2;
    // Enough segments that the straight edges stay within a quarter pixel
    // of the true circle.
    final n = outer < 1
        ? 3
        : (pi / acos(max(-1.0, 1 - 0.25 / outer))).ceil().clamp(32, 360);
    final points = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final a = 2 * pi * i / n;
      final dir = Offset(cos(a), sin(a));
      points
        ..add(center + dir * outer)
        ..add(center + dir * inner);
    }
    return ui.Vertices(VertexMode.triangleStrip, points);
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

  /// One pip per kill of the current streak under the score, in the
  /// streak's colour, and "TURBO" beside them: faint until turbo is on,
  /// then flashing.
  void _paintStreak(Canvas canvas) {
    if (game.phase != GamePhase.playing) return;
    const pip = 10.0;
    const gap = 6.0;
    const top = 50.0;
    final color = GameColors.of(game.streakMask);
    for (var i = 0; i < Game.streakLength; i++) {
      final rect = Rect.fromLTWH(16 + i * (pip + gap), top, pip, pip);
      if (i < game.streak) {
        canvas.drawRect(rect, Paint()..color = color);
      } else {
        canvas.drawRect(
          rect.deflate(0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white.withValues(alpha: 0.3),
        );
      }
    }
    const turboColor = Color(0xFFFF3DF5);
    final flashOn = sin(clock() * 8 * pi) > 0; // 4 flashes a second
    final tp = TextPainter(
      text: TextSpan(
        text: 'TURBO',
        style: TextStyle(
          color: !game.turbo
              ? Colors.white.withValues(alpha: 0.2)
              : flashOn
              ? turboColor
              : turboColor.withValues(alpha: 0.3),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: [
            if (game.turbo && flashOn)
              const Shadow(color: turboColor, blurRadius: 10),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        16 + Game.streakLength * (pip + gap) + 4,
        top + pip / 2 - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
