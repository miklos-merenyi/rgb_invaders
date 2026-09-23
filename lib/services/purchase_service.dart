import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';

// ── Product IDs ───────────────────────────────────────────────────────────────
// Consumable products; create them in App Store Connect and the Play Console.
// iOS uses reverse-domain IDs; Android does not allow dots.
const _kIosTipS = 'com.mermik.circles.tip_small';
const _kIosTipM = 'com.mermik.circles.tip_medium';
const _kIosTipL = 'com.mermik.circles.tip_large';

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

/// Show the tip jar every N games (in place of that game's ad), as long as
/// ads aren't currently suppressed.
const kTipPromptEvery = 20;

// ── SharedPreferences keys ────────────────────────────────────────────────────
const _kAdsFreeUntilMs = 'ads_free_until_ms';
const _kGamesPlayed = 'games_played';

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

  /// True when the game just finished should be followed by the tip jar.
  bool get shouldShowTipPrompt =>
      !adsRemoved && _gamesPlayed > 0 && _gamesPlayed % kTipPromptEvery == 0;

  /// True when the game just finished should be followed by an ad.
  bool get shouldShowAd =>
      !adsRemoved &&
      !shouldShowTipPrompt &&
      _gamesPlayed > 0 &&
      _gamesPlayed % kAdEveryNGames == 0;

  ProductDetails? product(String id) => _products[id];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _gamesPlayed = prefs.getInt(_kGamesPlayed) ?? 0;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGamesPlayed, _gamesPlayed);
    notifyListeners();
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
