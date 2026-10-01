import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ad_service.dart';
import '../services/leaderboard_service.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../widgets/share_app.dart';
import '../widgets/tip_jar.dart';
import 'chord_detector.dart';
import 'color_pad.dart';
import 'demo_player.dart';
import 'game.dart';
import 'game_painter.dart';
import 'share_card.dart';
import 'tutorial.dart';

/// Build with `--dart-define=DEMO=true` to make the game start and play
/// itself for a while, e.g. for store screenshots on a simulator. Off in
/// normal builds, where the compiler drops the demo code.
const _kDemo = bool.fromEnvironment('DEMO');

/// How long the demo plays (counted from its first game, across restarts)
/// before it stops firing, loses, and stays on the game-over screen. Sized so
/// a 2-minute recording ends on game over; `--dart-define=DEMO_SECONDS=n`
/// changes it.
const _kDemoSeconds = int.fromEnvironment('DEMO_SECONDS', defaultValue: 105);

/// Wave the demo starts at (`--dart-define=DEMO_WAVE=3`); later waves send
/// more invaders at once, giving the demo player room to build turbo streaks.
const _kDemoWave = int.fromEnvironment('DEMO_WAVE', defaultValue: 1);

/// Opens the tip jar over the demo's final game-over screen
/// (`--dart-define=DEMO_TIPJAR=true`), for its store screenshot.
const _kDemoTipJar = bool.fromEnvironment('DEMO_TIPJAR');

/// The app's numeric Apple ID (App Store Connect → App Information → Apple
/// ID), so "Rate the app" can open the App Store's review page. While it's
/// empty, iOS asks for the in-app rating prompt instead, which Apple shows at
/// most three times a year.
const _kAppStoreId = '';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.game});

  final Game? game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Game _game = (widget.game ?? Game())
    ..onHit = _sounds.explosion
    ..onMiss = _sounds.miss
    ..onWave = ((_) {
      _sounds.start();
      _sounds.waveMusic();
    })
    ..onBoss = (() {
      _sounds.start();
      _sounds.bossMusic(_game.wave);
    })
    ..onTurbo = (() {
      _demoLog('TURBO');
      _sounds.start();
    })
    ..onClear = ((masks) {
      _demoLog('CLEAR');
      masks.forEach(_sounds.explosion);
    });
  final _sounds = SoundService();
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _clock = 0;
  GamePhase _shownPhase = GamePhase.ready;

  /// False between a game ending and its ad (if any) being dismissed, so the
  /// game-over screen can't be tapped away just as an ad appears.
  bool _overlayReady = true;

  /// The tutorial while it runs, in a practice round.
  Tutorial? _tutorial;

  /// Turns near-simultaneous button presses into one mixed colour.
  late final ChordDetector _chords = ChordDetector(onChord: _fire);

  @override
  void initState() {
    super.initState();
    _game.best = max(_game.best, LeaderboardService().best);
    _ticker = createTicker(_tick)..start();
    if (_kDemo) {
      // Wall-clock time of the first frame, to line up the logged sounds
      // (see SoundService) with a screen recording.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) =>
            debugPrint('DEMO_FRAME ${DateTime.now().microsecondsSinceEpoch}'),
      );
      Future<void>.delayed(const Duration(seconds: 3), () {
        _demoClock.start();
        _startGame();
      });
    }
  }

  /// Logs a game event with a wall-clock timestamp in demo builds, to find
  /// it in a screen recording (see COMMANDS.md).
  void _demoLog(String event) {
    if (!_kDemo) return;
    debugPrint('DEMO_EVENT ${DateTime.now().microsecondsSinceEpoch} $event');
  }

  /// True while the demo player is holding buttons down.
  bool _demoPressing = false;

  final _demoClock = Stopwatch();

  /// True once the demo has played for [_kDemoSeconds] and should lose.
  bool get _demoGivingUp =>
      _demoClock.elapsed.inMilliseconds > _kDemoSeconds * 1000;

  /// Game time before which the demo player won't fire its next shot.
  double? _demoWaitUntil;
  final _demoRandom = Random();

  /// Demo player: presses the buttons for the colour [demoTarget] picks. It
  /// goes through the chord detector like real fingers, so the pads light up
  /// as in normal play.
  void _demoTurn() {
    if (_demoPressing || !_game.canFire || _demoGivingUp) return;
    final target = demoTarget(_game);
    if (target == null) {
      _demoWaitUntil = null;
      return;
    }
    // Vary the reaction time like a person: usually quick, sometimes slow.
    final waitUntil = _demoWaitUntil ??=
        _game.time + 0.05 + pow(_demoRandom.nextDouble(), 2) * 0.6;
    if (_game.time < waitUntil) return;
    _demoWaitUntil = null;
    _demoPressing = true;
    // Now and then pick the wrong colour, as people do.
    var mask = target;
    if (_demoRandom.nextDouble() < 0.04) {
      final others = GameColors.all.where((m) => m != mask).toList();
      mask = others[_demoRandom.nextInt(others.length)];
    }
    final buttons = [
      for (final b in const [GameColors.red, GameColors.green, GameColors.blue])
        if (mask & b != 0) b,
    ];
    // Fingers land a few milliseconds apart, well inside the chord window.
    for (final (i, b) in buttons.indexed) {
      Future<void>.delayed(Duration(milliseconds: 25 * i), () {
        if (mounted) setState(() => _chords.down(-b, b));
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      _demoPressing = false;
      if (!mounted) return;
      setState(() {
        for (final b in buttons) {
          _chords.up(-b);
        }
      });
    });
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock += dt;
    _game.update(dt);
    if (_tutorial?.update(dt) ?? false) {
      // The boss's music ends with it.
      if (_tutorial!.finished) _sounds.waveMusic();
      setState(() {});
    }
    if (_kDemo) _demoTurn();
    _frame.value++;
    if (_game.phase != _shownPhase) {
      setState(() => _shownPhase = _game.phase);
      if (_shownPhase == GamePhase.over) {
        _sounds.stopMusic();
        _sounds.gameOver();
        _afterGameOver();
      }
    }
  }

  /// Counts the game and submits its score, then shows an ad once
  /// [kAdMinGames] games and [kAdMinGap] have passed since the last one,
  /// followed by the tip jar every [kTipJarEveryNthBreak]th time, unless a
  /// tip removed ads. Otherwise a good enough score may offer
  /// leaderboard sign-in.
  Future<void> _afterGameOver() async {
    if (_kDemo) {
      // No ads or prompts in the demo. An early loss plays again after a
      // moment; the planned one at the end stays on the game-over screen.
      if (_demoGivingUp) {
        if (!_kDemoTipJar) return;
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) await showTipJar(context);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) _startGame();
      return;
    }
    setState(() => _overlayReady = false);
    final score = _game.score;
    final lb = LeaderboardService();
    lb.recordScore(score);
    // Let the player see what hit the bottom before anything pops up.
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final ps = PurchaseService();
    await ps.incrementGames();
    final tipJar = ps.tipJarDue;
    if (ps.adBreakDue) {
      await AdService().showIfReady();
      await ps.adBreakTaken();
    }
    if (!mounted) return;
    setState(() => _overlayReady = true);
    if (tipJar) {
      await showTipJar(context);
    } else if (lb.shouldPromptFor(score)) {
      await _promptLeaderboard(score);
    }
  }

  String get _platformGames => Platform.isIOS ? 'Game Center' : 'Play Games';

  /// Offers sign-in so [score] (and later ones) go on the global leaderboard.
  Future<void> _promptLeaderboard(int score) async {
    final lb = LeaderboardService();
    final signIn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Submit to leaderboard?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Sign in with $_platformGames to put your score on the global '
          'leaderboard. Your later scores will be submitted automatically.',
          style: const TextStyle(color: Colors.white60, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'No thanks',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Sign in',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
    // Dismissing the dialog just skips it for this launch.
    await lb.prompted(declined: signIn == false);
    // Signing in posts the saved best, which includes this score.
    if (signIn == true) await lb.signIn();
  }

  Future<void> _openLeaderboard() async {
    if (await LeaderboardService().show() || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't sign in to $_platformGames")),
    );
  }

  void _fire(int mask) {
    if (_game.fire(mask)) {
      _sounds.fire(mask);
    } else if (_game.phase == GamePhase.playing) {
      _sounds.dud(); // a circle is still out
    }
  }

  void _onButtonDown(PointerDownEvent e, int mask) {
    if (_game.phase != GamePhase.playing) return;
    setState(() => _chords.down(e.pointer, mask));
  }

  void _onButtonUp(PointerEvent e) {
    setState(() => _chords.up(e.pointer));
  }

  void _startGame() {
    if (!_overlayReady) return;
    _tutorial = null;
    _chords.reset();
    _game.start();
    if (_kDemo) _game.wave = _kDemoWave;
    _sounds.start();
    _sounds.newGameMusic();
    setState(() => _shownPhase = _game.phase);
  }

  void _startTutorial() {
    if (!_overlayReady) return;
    _chords.reset();
    _tutorial = Tutorial(_game)..begin();
    _sounds.start();
    _sounds.newGameMusic();
    setState(() => _shownPhase = _game.phase);
  }

  /// Leaves the tutorial for the start screen.
  void _endTutorial() {
    _tutorial = null;
    _chords.reset();
    _game.stop();
    _sounds.stopMusic();
    setState(() => _shownPhase = _game.phase);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _chords.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: GamePainter(
                      game: _game,
                      clock: () => _clock,
                      heldMask: () => _chords.held,
                      repaint: _frame,
                    ),
                  ),
                  if (_shownPhase == GamePhase.ready ||
                      _shownPhase == GamePhase.over && _overlayReady)
                    _buildOverlay(),
                  if (_tutorial case final tutorial?)
                    tutorial.finished
                        ? _buildTutorialEnd(tutorial.text)
                        : _buildTutorialCard(tutorial.text),
                  Positioned(top: 4, right: 4, child: _buildSoundButtons()),
                ],
              ),
            ),
            _buildButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final over = _shownPhase == GamePhase.over;
    const title = TextStyle(
      color: Colors.white,
      fontSize: 44,
      fontWeight: FontWeight.w900,
      letterSpacing: 4,
    );
    const body = TextStyle(color: Colors.white70, fontSize: 17, height: 1.5);
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      // Scale down on short screens rather than overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            over
                ? _rainbowText('GAME OVER', title)
                : _rainbowText('RGB INVADERS', title, colors: _titleColors),
            const SizedBox(height: 24),
            if (over) ...[
              Text(
                'Score: ${_game.score}',
                style: body.copyWith(color: Colors.white, fontSize: 24),
              ),
              Text('Best: ${_game.best}', style: body),
            ] else
              _tutorialText(
                'Mix RED, GREEN and BLUE\nto blast the invaders!',
                body.copyWith(color: Colors.white, fontSize: 20),
              ),
            const SizedBox(height: 32),
            _buildMenuButton(
              over ? 'Play Again' : 'Start Game',
              _startGame,
              primary: true,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMenuButton('Tutorial', _startTutorial, width: 124),
                const SizedBox(width: 12),
                _buildMenuButton('Instructions', _showInstructions, width: 124),
              ],
            ),
            const SizedBox(height: 40),
            if (over) _buildShareLink(),
            _buildRateLink(),
            _buildShareAppLink(),
            if (LeaderboardService().enabled) _buildLeaderboardLink(),
            _buildSupportLink(),
            _buildMusicLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    String label,
    VoidCallback onTap, {
    bool primary = false,
    double width = 260,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: primary ? Colors.white : Colors.white38,
            width: 1.5,
          ),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: GameColors.of(
                      GameColors.blue,
                    ).withValues(alpha: 0.6),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? Colors.black : Colors.white,
            fontSize: primary ? 24 : (width < 200 ? 16 : 20),
            fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  /// Colour names in tutorial text, by their mask.
  static const _colourWords = {
    'RED': GameColors.red,
    'GREEN': GameColors.green,
    'YELLOW': GameColors.red | GameColors.green,
    'BLUE': GameColors.blue,
    'MAGENTA': GameColors.red | GameColors.blue,
    'CYAN': GameColors.green | GameColors.blue,
    'WHITE': 7,
  };

  /// [text] with its capitalised colour names in bold, in their colour.
  Widget _tutorialText(
    String text,
    TextStyle style, {
    TextAlign textAlign = TextAlign.center,
  }) {
    final spans = <TextSpan>[];
    text.splitMapJoin(
      RegExp(r'\b[A-Z]{3,}\b'),
      onMatch: (m) {
        final mask = _colourWords[m[0]];
        spans.add(
          TextSpan(
            text: m[0],
            style: mask == null
                ? style.copyWith(fontWeight: FontWeight.w800)
                : style.copyWith(
                    color: GameColors.of(mask),
                    fontWeight: FontWeight.w800,
                  ),
          ),
        );
        return '';
      },
      onNonMatch: (t) {
        spans.add(TextSpan(text: t, style: style));
        return '';
      },
    );
    return Text.rich(TextSpan(children: spans), textAlign: textAlign);
  }

  /// The current tutorial step's instructions, above the launcher, out of
  /// the way of the invaders coming in at the top.
  Widget _buildTutorialCard(String text) {
    return Positioned(
      bottom: 64,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tutorialText(
              text,
              const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
            ),
            TextButton(
              onPressed: _endTutorial,
              child: const Text(
                'Skip tutorial',
                style: TextStyle(fontSize: 13, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tutorial's closing card, with the way into a real game.
  Widget _buildTutorialEnd(String text) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rainbowText(
              "YOU'RE READY!",
              const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 24),
            _tutorialText(
              text,
              const TextStyle(color: Colors.white70, fontSize: 17, height: 1.5),
            ),
            const SizedBox(height: 32),
            _buildMenuButton('Start Game', _startGame, primary: true),
            const SizedBox(height: 12),
            _buildMenuButton('Back to Menu', _endTutorial),
          ],
        ),
      ),
    );
  }

  /// "RGB" in its own colours, then "INVADERS" in the icon's rainbow.
  static const _titleColors = [
    GameColors.red,
    GameColors.green,
    GameColors.blue,
    ...GameColors.rainbow,
  ];

  /// [text] with each letter in the next of [colors] (by default the app
  /// icon's rainbow), glowing in its own colour.
  Widget _rainbowText(
    String text,
    TextStyle style, {
    List<int> colors = GameColors.rainbow,
  }) {
    final letters = <TextSpan>[];
    var i = 0;
    for (final ch in text.split('')) {
      if (ch == ' ') {
        letters.add(TextSpan(text: ch, style: style));
        continue;
      }
      final color = GameColors.of(colors[i++ % colors.length]);
      letters.add(
        TextSpan(
          text: ch,
          style: style.copyWith(
            color: color,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.7), blurRadius: 16),
            ],
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: letters));
  }

  /// Music and sound-effect switches, side by side.
  Widget _buildSoundButtons() {
    return ListenableBuilder(
      listenable: _sounds,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _sounds.toggleMusic,
            tooltip: _sounds.musicEnabled ? 'Music off' : 'Music on',
            icon: Icon(
              _sounds.musicEnabled ? Icons.music_note : Icons.music_off,
              color: Colors.white38,
            ),
          ),
          IconButton(
            onPressed: _sounds.toggle,
            tooltip: _sounds.enabled ? 'Mute' : 'Unmute',
            icon: Icon(
              _sounds.enabled ? Icons.volume_up : Icons.volume_off,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  static const _linkStyle = TextStyle(
    fontSize: 13,
    color: Colors.white54,
    decoration: TextDecoration.underline,
    decorationColor: Colors.white24,
    letterSpacing: 1,
  );

  /// Bigger and brighter than [_linkStyle], for the links we most want
  /// tapped.
  static const _mainLinkStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    decoration: TextDecoration.underline,
    decorationColor: Colors.white54,
    letterSpacing: 1,
  );

  Widget _buildRateLink() {
    return GestureDetector(
      onTap: _rateApp,
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Text('⭐ Rate the app', style: _mainLinkStyle),
      ),
    );
  }

  Widget _buildShareAppLink() {
    return GestureDetector(
      onTap: () => showShareApp(context),
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: Text('📲 Share the app', style: _mainLinkStyle),
      ),
    );
  }

  /// Opens the store's review page; on iOS without [_kAppStoreId], the
  /// in-app rating prompt.
  Future<void> _rateApp() async {
    final review = InAppReview.instance;
    try {
      if (Platform.isIOS && _kAppStoreId.isEmpty) {
        if (await review.isAvailable()) await review.requestReview();
      } else {
        await review.openStoreListing(appStoreId: _kAppStoreId);
      }
    } catch (e) {
      debugPrint('[GameScreen] rating failed: $e');
    }
  }

  Widget _buildLeaderboardLink() {
    return GestureDetector(
      onTap: _openLeaderboard,
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Text('🏆 Leaderboard', style: _linkStyle),
      ),
    );
  }

  Widget _buildMusicLink() {
    return GestureDetector(
      onTap: _showMusicCredits,
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Text('🎵 About the music', style: _linkStyle),
      ),
    );
  }

  /// The rules in full, for reading at leisure.
  Future<void> _showInstructions() {
    const body = TextStyle(color: Colors.white60, height: 1.5, fontSize: 14);
    const heading = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      height: 1.5,
    );
    const sections = [
      (
        'Fire',
        'Tap RED, GREEN or BLUE to fire a ring of that colour. A ring only '
            'destroys invaders of its own colour and passes through the rest. '
            'Only one ring flies at a time.',
      ),
      (
        'Mix colours',
        'Press buttons together to mix:\n'
            'RED + GREEN = YELLOW\n'
            'GREEN + BLUE = CYAN\n'
            'RED + BLUE = MAGENTA\n'
            'All three = WHITE',
      ),
      (
        'Score',
        'Each invader scores 1 point per button it takes: 1 for primary '
            'colours, 2 for mixed ones, 3 for WHITE.',
      ),
      (
        'Waves',
        'Every ${Game.waveLength} invaders a new wave begins. It starts '
            'slower again, but the invaders come in pairs, then threes, '
            'fours and fives.',
      ),
      (
        'Bosses',
        'Between waves a boss comes down. Only its lowest colour hurts it: '
            'shoot it away band by band for a +${Game.bossBonus} bonus. A '
            'wrong colour pushes it closer.',
      ),
      (
        'Turbo',
        'Hit ${Game.streakLength} of one colour in a row for TURBO, then '
            '${Game.streakLength} more in a row to clear the whole screen '
            'for a +${Game.turboBonus} bonus. A ring that hits nothing '
            'breaks the streak.',
      ),
      (
        'Game over',
        'If a single invader, or the boss, reaches the bottom, the game '
            'is over.',
      ),
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'How to play',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (title, text) in sections) ...[
              Text(title, style: heading),
              _tutorialText(text, body, textAlign: TextAlign.start),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _showMusicCredits() {
    const body = TextStyle(color: Colors.white60, height: 1.5);
    const heading = TextStyle(
      color: Colors.white70,
      fontWeight: FontWeight.w600,
      height: 1.5,
    );
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'About the music',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('During the waves', style: heading),
            Text(
              'Rumination Blues\n© 2026 Miklos Merenyi. All rights reserved.',
              style: body,
            ),
            SizedBox(height: 16),
            Text('During the boss fights', style: heading),
            Text(
              "Excerpts from Modest Mussorgsky's 'Pictures at an Exhibition' "
              "(Gnomus; The Hut on Hen's Legs), from the edition typeset by "
              'Knute Snortum for the Mutopia Project (mutopiaproject.org).\n'
              'Excerpted and rendered by Miklos Merenyi.\n'
              'Licensed under CC BY-SA 4.0 '
              '(creativecommons.org/licenses/by-sa/4.0).',
              style: body,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildShareLink() {
    // A Builder, so the share sheet on iPad can point at this link.
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () => _shareScore(context),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Text('📤 Share score', style: _mainLinkStyle),
        ),
      ),
    );
  }

  bool _sharing = false;

  /// Shares a card with the score and a QR code to the game, plus a message
  /// with the same link.
  Future<void> _shareScore(BuildContext linkContext) async {
    if (_sharing) return;
    _sharing = true;
    final box = linkContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final score = _game.score;
    final wave = _game.wave;
    try {
      final png = await renderShareCard(score: score, wave: wave);
      await SharePlus.instance.share(
        ShareParams(
          text: shareMessage(score: score, wave: wave),
          files: [
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: 'rgb_invaders_score.png',
            ),
          ],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      debugPrint('[GameScreen] share failed: $e');
    } finally {
      _sharing = false;
    }
  }

  Widget _buildSupportLink() {
    final ps = PurchaseService();
    return ListenableBuilder(
      listenable: ps,
      builder: (context, _) => GestureDetector(
        onTap: () => showTipJar(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            ps.adsRemoved
                ? adsFreeLabel(context, ps.adsFreeUntil!)
                : '☕ Support the dev & remove ads',
            style: ps.adsRemoved
                ? _mainLinkStyle.copyWith(color: Colors.greenAccent)
                : _mainLinkStyle,
          ),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    final held = _chords.held;
    final litColor = GameColors.of(held);
    return ListenableBuilder(
      // Rebuilt every frame so the pads dim while a circle is on screen.
      listenable: _frame,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 110,
            child: Row(
              children: [
                for (final mask in const [
                  GameColors.red,
                  GameColors.green,
                  GameColors.blue,
                ])
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _onButtonDown(e, mask),
                      onPointerUp: _onButtonUp,
                      onPointerCancel: _onButtonUp,
                      child: ColorPad(
                        mask: mask,
                        pressed: _chords.isHeld(mask),
                        litColor: litColor,
                        ready: _game.canFire,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          MixLegend(held: held),
        ],
      ),
    );
  }
}
