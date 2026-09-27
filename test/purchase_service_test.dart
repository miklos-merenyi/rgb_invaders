import 'package:rgb_invaders/services/purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ad every 3rd game, tip jar instead of the ad every 20th', () async {
    final ps = PurchaseService();
    final ads = <int>[];
    final tips = <int>[];
    while (ps.gamesPlayed < 60) {
      await ps.incrementGames();
      if (ps.shouldShowAd) ads.add(ps.gamesPlayed);
      if (ps.shouldShowTipPrompt) tips.add(ps.gamesPlayed);
    }
    // Game 60 is due both; the tip jar replaces the ad.
    expect(ads, [for (var n = 3; n < 60; n += 3) n]);
    expect(tips, [20, 40, 60]);
  });
}
