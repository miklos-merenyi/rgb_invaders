import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ── Ad unit IDs ───────────────────────────────────────────────────────────────
// Same setup as rigobert. The kTest* IDs are Google's official test IDs: safe
// during development, they never generate revenue or policy risk.
//
// TODO: create the RGB Invaders app and interstitial units in the AdMob console
// (https://admob.google.com) and fill in the kRelease* IDs below, plus the
// AdMob *app* IDs in AndroidManifest.xml and ios/Runner/Info.plist.
// While a release ID is empty, release builds simply show no ads.

const _kTestAndroidInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
const _kTestIosInterstitialId = 'ca-app-pub-3940256099942544/4411468910';

const _kReleaseAndroidInterstitialId = '';
const _kReleaseIosInterstitialId = '';

String get _interstitialAdUnitId {
  if (kDebugMode) {
    return Platform.isIOS
        ? _kTestIosInterstitialId
        : _kTestAndroidInterstitialId;
  }
  return Platform.isIOS
      ? _kReleaseIosInterstitialId
      : _kReleaseAndroidInterstitialId;
}

/// Show an interstitial ad every N games (unless a tip removed ads).
const kAdEveryNGames = 5;

class AdService {
  static final AdService _instance = AdService._();
  factory AdService() => _instance;
  AdService._();

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  bool _initialised = false;

  /// Call once from main().
  Future<void> init() async {
    if (_interstitialAdUnitId.isEmpty) return;
    // Cap ad content to "G" and tag requests as child-directed, as rigobert
    // does: its store review rejected ads that exceeded the app's rating.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.g,
        ageRestrictedTreatment: AgeRestrictedTreatment.child,
      ),
    );
    await MobileAds.instance.initialize();
    _initialised = true;
    _loadInterstitial();
  }

  void _loadInterstitial() {
    if (!_initialised || _isLoading || _interstitialAd != null) return;
    _isLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
          debugPrint('[AdService] interstitial loaded');
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          _interstitialAd = null;
          debugPrint('[AdService] failed to load interstitial: $error');
        },
      ),
    );
  }

  /// Shows the interstitial (if one is ready) and resolves when the player
  /// dismisses it, then starts loading the next one.
  /// Returns true if an ad was shown, false if none was ready.
  Future<bool> showIfReady() async {
    final ad = _interstitialAd;
    if (ad == null) {
      debugPrint('[AdService] no ad ready, skipping');
      _loadInterstitial();
      return false;
    }

    _interstitialAd = null; // claim it before showing

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        completer.complete();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdService] failed to show interstitial: $error');
        ad.dispose();
        completer.complete();
        _loadInterstitial();
      },
    );

    await ad.show();
    await completer.future;
    return true;
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
