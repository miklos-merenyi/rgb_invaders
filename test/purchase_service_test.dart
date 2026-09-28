import 'package:rgb_invaders/services/purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // PurchaseService is a singleton, so these tests share one instance and
  // run in order.
  var now = DateTime(2026);
  final ps = PurchaseService()..clock = (() => now);

  /// Starts right after the tip jar, so the next 19 games can't hit it,
  /// with a fresh ad break.
  Future<void> startAfterTipJar() async {
    while (!ps.shouldShowTipPrompt) {
      await ps.incrementGames();
    }
    await ps.adBreakShown();
  }

  /// Plays a game lasting [seconds], then shows an ad if one is due.
  /// Returns whether it did.
  Future<bool> play(int seconds) async {
    now = now.add(Duration(seconds: seconds));
    await ps.incrementGames();
    if (!ps.shouldShowAd) return false;
    await ps.adBreakShown();
    return true;
  }

  test('quick games wait for 150 seconds since the last ad', () async {
    await startAfterTipJar();
    final ads = [for (var i = 0; i < 12; i++) await play(20)];
    // 20-second games: the 8th game is the first past 150 seconds.
    expect(ads, List.generate(12, (i) => i == 7));
  });

  test('long games still wait for two games', () async {
    await startAfterTipJar();
    final ads = [for (var i = 0; i < 6; i++) await play(300)];
    expect(ads, [false, true, false, true, false, true]);
  });

  test('an ad that was not shown is due after the next game', () async {
    await startAfterTipJar();
    now = now.add(const Duration(minutes: 10));
    await ps.incrementGames();
    await ps.incrementGames();
    expect(ps.shouldShowAd, isTrue);
    // No adBreakShown(): the ad wasn't loaded.
    await ps.incrementGames();
    expect(ps.shouldShowAd, isTrue);
  });

  test('the tip jar replaces the ad every 20th game', () async {
    await ps.adBreakShown();
    final tips = <int>[];
    final start = ps.gamesPlayed;
    while (ps.gamesPlayed < start + 60) {
      now = now.add(const Duration(minutes: 5));
      await ps.incrementGames();
      if (ps.shouldShowTipPrompt) {
        expect(ps.shouldShowAd, isFalse);
        tips.add(ps.gamesPlayed);
        await ps.adBreakShown();
      } else if (ps.shouldShowAd) {
        await ps.adBreakShown();
      }
    }
    expect(tips.length, 3);
    expect(tips.every((n) => n % 20 == 0), isTrue);
  });
}
