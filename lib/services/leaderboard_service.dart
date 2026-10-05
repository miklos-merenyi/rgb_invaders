import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform.dart';

// ── Leaderboard IDs ───────────────────────────────────────────────────────────
// One global leaderboard, via Game Center on iOS and macOS and Play Games on
// Android.
// The Play Games project ID lives in
// android/app/src/main/res/values/games-ids.xml. While the ID for the current
// platform is empty (as on the web), leaderboards are switched off and never
// touch the SDK.

const _kIosLeaderboardId = 'com.mermik.rgbinvaders.highscores';
const _kAndroidLeaderboardId = 'CgkI09qroLsNEAIQAA';

String get _leaderboardId => !hasStore
    ? ''
    : isApple
    ? _kIosLeaderboardId
    : _kAndroidLeaderboardId;

/// Scores below this are not submitted, and don't trigger the sign-in prompt.
const kLeaderboardMinScore = 20;

// ── SharedPreferences keys ────────────────────────────────────────────────────
// Set once the player has signed in, so later launches can sign in silently
// without Android showing its account picker to someone who never asked.
const _kHasSignedIn = 'leaderboard_has_signed_in';
// Set when the player says "No thanks" to the prompt; cleared on sign-in.
const _kOptedOut = 'leaderboard_opted_out';
// The player's best score on this device, posted after any sign-in so bests
// set while signed out still reach the leaderboard.
const _kBest = 'best_score';

class LeaderboardService extends ChangeNotifier {
  static final LeaderboardService _instance = LeaderboardService._();
  factory LeaderboardService() => _instance;
  LeaderboardService._();

  bool _signedIn = false;
  bool _hasSignedIn = false;
  bool _optedOut = false;
  bool _promptedThisSession = false;
  int _best = 0;

  /// False until the leaderboard IDs for this platform are filled in.
  bool get enabled => _leaderboardId.isNotEmpty;

  bool get isSignedIn => _signedIn;

  /// The best score saved on this device.
  int get best => _best;

  /// True when the game just finished with [score] should offer sign-in:
  /// at most once per launch, and never after the player declined.
  bool shouldPromptFor(int score) =>
      enabled &&
      !_signedIn &&
      !_optedOut &&
      !_promptedThisSession &&
      score >= kLeaderboardMinScore;

  /// Call once from main(). Loads the saved best and flags, then signs in
  /// in the background (see [_autoSignIn]).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _best = prefs.getInt(_kBest) ?? 0;
    if (!enabled) return;
    _hasSignedIn = prefs.getBool(_kHasSignedIn) ?? false;
    _optedOut = prefs.getBool(_kOptedOut) ?? false;
    _autoSignIn();
  }

  /// Signs in without the player asking:
  /// - Picks up an existing session first. Play Games signs most Android
  ///   players in by itself at launch, and that shows no UI.
  /// - iOS and macOS always authenticate with Game Center, as Apple
  ///   recommends. For a signed-in player that's just the "Welcome back"
  ///   banner, and Game Center stops asking players who keep cancelling.
  /// - Android only calls signIn() for a player who signed in before, since
  ///   otherwise it would show the account picker on every launch.
  /// Once signed in, posts the saved best.
  Future<void> _autoSignIn() async {
    try {
      if (await GamesServices.isSignedIn) {
        await _markSignedIn();
      } else if (isApple || _hasSignedIn) {
        await GamesServices.signIn();
        await _markSignedIn();
      }
    } catch (e) {
      debugPrint('[LeaderboardService] auto sign-in skipped: $e');
    }
    if (_signedIn) await submitBest();
  }

  Future<void> _markSignedIn() async {
    _signedIn = true;
    notifyListeners();
    if (_hasSignedIn) return;
    _hasSignedIn = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSignedIn, true);
  }

  /// Shows the platform sign-in UI. On success, remembers it, turns
  /// submission back on if the player had declined before, and posts the
  /// saved best.
  Future<bool> signIn() async {
    if (!enabled) return false;
    try {
      await GamesServices.signIn();
      await _markSignedIn();
    } catch (e) {
      debugPrint('[LeaderboardService] sign-in failed: $e');
      _signedIn = false;
      notifyListeners();
      return false;
    }
    _optedOut = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptedOut, false);
    await submitBest();
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

  /// Saves [score] if it's a new best, then posts it if signed in.
  Future<void> recordScore(int score) async {
    if (score > _best) {
      _best = score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBest, score);
    }
    await submitScore(score);
  }

  /// Posts the saved best. The platform keeps only each player's best, so
  /// posting one that's already there is harmless.
  Future<void> submitBest() => submitScore(_best);

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

  /// Opens the native leaderboard UI, signing in first if needed. Opening it
  /// also turns submission back on for a player who declined the prompt but
  /// was signed in by the platform anyway.
  /// Returns false if the player couldn't be signed in.
  Future<bool> show() async {
    if (!enabled) return false;
    if ((!_signedIn || _optedOut) && !await signIn()) return false;
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
