import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Leaderboard IDs ───────────────────────────────────────────────────────────
// One global leaderboard, via Game Center on iOS and Play Games on Android.
//
// TODO: create the leaderboard in App Store Connect (Game Center) and Play
// Console, then fill in the IDs below, plus the Play Games project ID in
// android/app/src/main/res/values/games-ids.xml. While the ID for the current
// platform is empty, leaderboards are switched off and never touch the SDK.

const _kIosLeaderboardId = '';
const _kAndroidLeaderboardId = '';

String get _leaderboardId =>
    Platform.isIOS ? _kIosLeaderboardId : _kAndroidLeaderboardId;

/// Scores below this are not submitted, and don't trigger the sign-in prompt.
const kLeaderboardMinScore = 20;

// ── SharedPreferences keys ────────────────────────────────────────────────────
// Set once the player has signed in, so later launches can sign in silently
// without Android showing its account picker to someone who never asked.
const _kHasSignedIn = 'leaderboard_has_signed_in';
// Set when the player says "No thanks" to the prompt; cleared on sign-in.
const _kOptedOut = 'leaderboard_opted_out';

class LeaderboardService extends ChangeNotifier {
  static final LeaderboardService _instance = LeaderboardService._();
  factory LeaderboardService() => _instance;
  LeaderboardService._();

  bool _signedIn = false;
  bool _hasSignedIn = false;
  bool _optedOut = false;
  bool _promptedThisSession = false;

  /// False until the leaderboard IDs for this platform are filled in.
  bool get enabled => _leaderboardId.isNotEmpty;

  bool get isSignedIn => _signedIn;

  /// True when the game just finished with [score] should offer sign-in:
  /// at most once per launch, and never after the player declined.
  bool shouldPromptFor(int score) =>
      enabled &&
      !_signedIn &&
      !_optedOut &&
      !_promptedThisSession &&
      score >= kLeaderboardMinScore;

  /// Call once from main(). Loads the saved flags and, for a returning
  /// player, signs in silently in the background.
  Future<void> init() async {
    if (!enabled) return;
    final prefs = await SharedPreferences.getInstance();
    _hasSignedIn = prefs.getBool(_kHasSignedIn) ?? false;
    _optedOut = prefs.getBool(_kOptedOut) ?? false;
    if (_hasSignedIn && !_optedOut) _signIn();
  }

  Future<bool> _signIn() async {
    try {
      await GamesServices.signIn();
      _signedIn = true;
    } catch (e) {
      debugPrint('[LeaderboardService] sign-in failed: $e');
      _signedIn = false;
    }
    notifyListeners();
    return _signedIn;
  }

  /// Shows the platform sign-in UI. On success, remembers it and turns
  /// submission back on if the player had declined before.
  Future<bool> signIn() async {
    if (!enabled) return false;
    if (!await _signIn()) return false;
    _hasSignedIn = true;
    _optedOut = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSignedIn, true);
    await prefs.setBool(_kOptedOut, false);
    return true;
  }

  /// Records that the prompt was shown; [declined] stops future prompts.
  Future<void> prompted({required bool declined}) async {
    _promptedThisSession = true;
    if (!declined) return;
    _optedOut = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptedOut, true);
  }

  /// Posts [score] if signed in and it's worth posting. The platform keeps
  /// only each player's best, so every game's score can be sent.
  Future<void> submitScore(int score) async {
    if (!enabled || !_signedIn || _optedOut) return;
    if (score < kLeaderboardMinScore) return;
    try {
      await GamesServices.submitScore(
        score: Score(
          iOSLeaderboardID: _kIosLeaderboardId,
          androidLeaderboardID: _kAndroidLeaderboardId,
          value: score,
        ),
      );
    } catch (e) {
      debugPrint('[LeaderboardService] submitScore failed: $e');
    }
  }

  /// Opens the native leaderboard UI, signing in first if needed.
  /// Returns false if the player couldn't be signed in.
  Future<bool> show() async {
    if (!enabled) return false;
    if (!_signedIn && !await signIn()) return false;
    try {
      await GamesServices.showLeaderboards(
        iOSLeaderboardID: _kIosLeaderboardId,
        androidLeaderboardID: _kAndroidLeaderboardId,
      );
    } catch (e) {
      debugPrint('[LeaderboardService] showLeaderboards failed: $e');
    }
    return true;
  }
}
