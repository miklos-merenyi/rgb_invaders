import 'package:rgb_invaders/services/purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // PurchaseService is a singleton, so these tests share one instance and
  // run in order.
  var now = DateTime(2026);
  final ps = PurchaseService()..clock = (() => now);

  /// Takes ad breaks until the tip jar has just been shown, so each test
  /// starts at the beginning of the ad, ad, ad + tip jar cycle.
  Future<void> startAfterTipJar() async {
    while (true) {
      now = now.add(const Duration(hours: 1));
      await ps.incrementGames();
      await ps.incrementGames();
      final tipJar = ps.tipJarDue;
      await ps.adBreakTaken();
      if (tipJar) return;
    }
  }

  /// Plays a game lasting [seconds], then takes the ad break if one is due,
  /// as the game-over screen does. Returns 'ad', 'ad+tip' or '-'.
  Future<String> play(int seconds) async {
    now = now.add(Duration(seconds: seconds));
    await ps.incrementGames();
    if (!ps.adBreakDue) return '-';
    final tipJar = ps.tipJarDue;
    await ps.adBreakTaken();
    return tipJar ? 'ad+tip' : 'ad';
  }

  test('quick games wait for 180 seconds since the last ad', () async {
    await startAfterTipJar();
    final shown = [for (var i = 0; i < 12; i++) await play(20)];
    // 20-second games: the 9th game is the first to reach 180 seconds.
    expect(shown, List.generate(12, (i) => i == 8 ? 'ad' : '-'));
  });

  test('long games still wait for two games', () async {
    await startAfterTipJar();
    final shown = [for (var i = 0; i < 6; i++) await play(300)];
    expect(shown, ['-', 'ad', '-', 'ad', '-', 'ad+tip']);
  });

  test('every 3rd ad break adds the tip jar after the ad', () async {
    await startAfterTipJar();
    final breaks = <String>[];
    while (breaks.length < 9) {
      final shown = await play(120);
      if (shown != '-') breaks.add(shown);
    }
    expect(breaks, [
      for (var i = 0; i < 3; i++) ...['ad', 'ad', 'ad+tip'],
    ]);
  });
}
