import 'package:rgb_invaders/services/purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ad every 5th game, tip jar instead of the ad every 20th', () async {
    final ps = PurchaseService();
    final ads = <int>[];
    final tips = <int>[];
    while (ps.gamesPlayed < 40) {
      await ps.incrementGames();
      if (ps.shouldShowAd) ads.add(ps.gamesPlayed);
      if (ps.shouldShowTipPrompt) tips.add(ps.gamesPlayed);
    }
    expect(ads, [5, 10, 15, 25, 30, 35]);
    expect(tips, [20, 40]);
  });
}
