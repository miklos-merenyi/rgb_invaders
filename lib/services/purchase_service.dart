import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';

// ── Product IDs ───────────────────────────────────────────────────────────────
// Consumable products; create them in App Store Connect and the Play Console.
// iOS uses reverse-domain IDs; Android does not allow dots.
const _kIosTipS = 'com.mermik.rgbinvaders.tip_small';
const _kIosTipM = 'com.mermik.rgbinvaders.tip_medium';
const _kIosTipL = 'com.mermik.rgbinvaders.tip_large';

const _kAndroidTipS = 'tip_small';
const _kAndroidTipM = 'tip_medium';
const _kAndroidTipL = 'tip_large';

final kProductTipS = Platform.isIOS ? _kIosTipS : _kAndroidTipS;
final kProductTipM = Platform.isIOS ? _kIosTipM : _kAndroidTipM;
final kProductTipL = Platform.isIOS ? _kIosTipL : _kAndroidTipL;

final kAllProductIds = {kProductTipS, kProductTipM, kProductTipL};

/// Ad-free time granted per tip tier, in calendar months. Tips stack: a new
/// tip extends whatever ad-free time is left rather than replacing it.
final kAdFreeMonths = {kProductTipS: 1, kProductTipM: 3, kProductTipL: 12};

/// Every Nth ad break shows the tip jar after its ad, so it follows the same
/// [kAdMinGames] and [kAdMinGap] rule and never shows while a tip keeps ads
/// away.
const kTipJarEveryNthBreak = 3;

// ── SharedPreferences keys ────────────────────────────────────────────────────
const _kAdsFreeUntilMs = 'ads_free_until_ms';
const _kGamesPlayed = 'games_played';
const _kGamesSinceAd = 'games_since_ad';
const _kLastAdMs = 'last_ad_ms';
const _kBreaksSinceTipJar = 'breaks_since_tip_jar';

class PurchaseService extends ChangeNotifier {
  static final PurchaseService _instance = PurchaseService._();
  factory PurchaseService() => _instance;
  PurchaseService._();

  // Looked up lazily so widget tests can use this service without the plugin.
  InAppPurchase get _iap => InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  DateTime? _adsFreeUntil;
  int _gamesPlayed = 0;
  int _gamesSinceAd = 0;
  int _breaksSinceTipJar = 0;
  // Starts at first launch, so a new player also waits [kAdMinGap].
  late DateTime _lastAdAt = clock();

  /// The time source, replaceable in tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  Map<String, ProductDetails> _products = {};
  bool _loadingPurchase = false;

  bool get available => _available;
  int get gamesPlayed => _gamesPlayed;
  bool get loadingPurchase => _loadingPurchase;

  /// When the current ad-free period ends, or null if none is active.
  DateTime? get adsFreeUntil => _adsFreeUntil;

  /// True while a tip's ad-free period is still active.
  bool get adsRemoved =>
      _adsFreeUntil != null && _adsFreeUntil!.isAfter(DateTime.now());

  /// True when the game just finished should be followed by an ad: enough
  /// games and time have passed since the last ad break.
  bool get adBreakDue =>
      !adsRemoved &&
      _gamesSinceAd >= kAdMinGames &&
      clock().difference(_lastAdAt) >= kAdMinGap;

  /// True when this ad break should also show the tip jar after the ad.
  bool get tipJarDue =>
      adBreakDue && _breaksSinceTipJar >= kTipJarEveryNthBreak - 1;

  ProductDetails? product(String id) => _products[id];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _gamesPlayed = prefs.getInt(_kGamesPlayed) ?? 0;
    _gamesSinceAd = prefs.getInt(_kGamesSinceAd) ?? 0;
    _breaksSinceTipJar = prefs.getInt(_kBreaksSinceTipJar) ?? 0;
    final lastAdMs = prefs.getInt(_kLastAdMs);
    if (lastAdMs != null) {
      _lastAdAt = DateTime.fromMillisecondsSinceEpoch(lastAdMs);
    } else {
      await prefs.setInt(_kLastAdMs, _lastAdAt.millisecondsSinceEpoch);
    }
    final storedMs = prefs.getInt(_kAdsFreeUntilMs);
    if (storedMs != null) {
      _adsFreeUntil = DateTime.fromMillisecondsSinceEpoch(storedMs);
    }

    _available = await _iap.isAvailable();
    if (!_available) {
      notifyListeners();
      return;
    }

    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate);

    try {
      final resp = await _iap.queryProductDetails(kAllProductIds);
      if (resp.error != null) debugPrint('IAP query error: ${resp.error}');
      if (resp.notFoundIDs.isNotEmpty) {
        debugPrint('IAP products not found: ${resp.notFoundIDs}');
      }
      _products = {for (final p in resp.productDetails) p.id: p};
    } catch (e) {
      debugPrint('IAP query exception: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> incrementGames() async {
    _gamesPlayed++;
    _gamesSinceAd++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGamesPlayed, _gamesPlayed);
    await prefs.setInt(_kGamesSinceAd, _gamesSinceAd);
    notifyListeners();
  }

  /// Ends a due ad break, whether or not an ad was loaded to show, and
  /// restarts the count towards the next one. Counting breaks without an ad
  /// keeps the tip jar coming when no ads load, e.g. before the release ad
  /// unit IDs are set.
  Future<void> adBreakTaken() async {
    _breaksSinceTipJar = tipJarDue ? 0 : _breaksSinceTipJar + 1;
    _gamesSinceAd = 0;
    _lastAdAt = clock();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGamesSinceAd, 0);
    await prefs.setInt(_kLastAdMs, _lastAdAt.millisecondsSinceEpoch);
    await prefs.setInt(_kBreaksSinceTipJar, _breaksSinceTipJar);
  }

  Future<void> buyTip(String productId) async {
    final details = _products[productId];
    if (details == null) {
      debugPrint('IAP error: product not found for ID: $productId');
      return;
    }

    _loadingPurchase = true;
    notifyListeners();
    try {
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
    } catch (e) {
      debugPrint('IAP error during purchase: $e');
    } finally {
      _loadingPurchase = false;
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _grantAdFreeTime(p.productID);
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('IAP error: ${p.error}');
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    _loadingPurchase = false;
    notifyListeners();
  }

  /// Extends the ad-free period by the tier's duration, stacking on top of any
  /// time still left.
  Future<void> _grantAdFreeTime(String productId) async {
    final months = kAdFreeMonths[productId];
    if (months == null) return;

    final now = DateTime.now();
    final base = (_adsFreeUntil != null && _adsFreeUntil!.isAfter(now))
        ? _adsFreeUntil!
        : now;
    _adsFreeUntil = DateTime(
      base.year,
      base.month + months,
      base.day,
      base.hour,
      base.minute,
      base.second,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAdsFreeUntilMs, _adsFreeUntil!.millisecondsSinceEpoch);
  }
}
