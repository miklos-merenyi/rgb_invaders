import 'game.dart';

/// Chooses what the demo player (see `_kDemo` in game_screen.dart) fires at
/// next: the colour, or null to hold fire for now. It plays for turbo,
/// keeping to its streak's colour and waiting for more of it, and only
/// breaks the streak when an invader gets too close to the bottom.
int? demoTarget(Game g) {
  final boss = g.boss;
  if (boss != null) {
    final bottom = g.bossBandRect(boss, boss.alive - 1).bottom;
    return bottom < g.size.height * 0.2 ? null : boss.target;
  }
  final visible = g.monsters.where((m) => m.y > 0.05).toList();
  if (visible.isEmpty) return null;
  final lowest = visible.reduce((a, m) => m.y > a.y ? m : a);
  if (lowest.y > demoDangerY) return lowest.mask;
  if (g.streak > 0) {
    return visible.any((m) => m.mask == g.streakMask) ? g.streakMask : null;
  }
  // Start a streak in the commonest colour on screen, once it's in play.
  final counts = <int, int>{};
  for (final m in visible) {
    counts[m.mask] = (counts[m.mask] ?? 0) + 1;
  }
  final best = counts.entries.reduce((a, e) => e.value > a.value ? e : a);
  return lowest.y > 0.2 ? best.key : null;
}

/// How far down (as a fraction of the play-field) an invader may come
/// before the demo player shoots it whatever its colour.
const demoDangerY = 0.8;
