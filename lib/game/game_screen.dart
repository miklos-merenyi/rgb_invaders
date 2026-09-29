import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ad_service.dart';
import '../services/leaderboard_service.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../widgets/tip_jar.dart';
import 'chord_detector.dart';
import 'color_pad.dart';
import 'demo_player.dart';
import 'game.dart';
import 'game_painter.dart';
import 'share_card.dart';

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
        _onOverlayTap();
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
      if (mounted) _onOverlayTap();
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

  void _onOverlayTap() {
    if (!_overlayReady) return;
    _chords.reset();
    _game.start();
    if (_kDemo) _game.wave = _kDemoWave;
    _sounds.start();
    _sounds.newGameMusic();
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onOverlayTap,
      child: Container(
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
                const Text(
                  'Tap a colour button to fire a circle.\n'
                  'Press several buttons together to mix colours:\n'
                  'R+G = yellow, G+B = cyan, R+B = magenta,\n'
                  'R+G+B = white.\n'
                  'A circle only destroys a monster of its own colour.\n'
                  'Mixed colours score more: 1 point per button.\n'
                  'Every 25 monsters a new wave starts slower again,\n'
                  'but they come in pairs, then threes…\n'
                  'Between waves a boss descends: shoot its\n'
                  'lowest colour to peel it away, band by band.\n'
                  'Hit 5 of one colour in a row for TURBO,\n'
                  'then 5 more in a row to clear the screen!',
                  textAlign: TextAlign.center,
                  style: body,
                ),
              const SizedBox(height: 32),
              const Text(
                'Tap to play',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),
              if (over) _buildShareLink(),
              if (LeaderboardService().enabled) _buildLeaderboardLink(),
              _buildMusicLink(),
              _buildSupportLink(),
            ],
          ),
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
          padding: EdgeInsets.all(8),
          child: Text('📤 Share score', style: _linkStyle),
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
          padding: const EdgeInsets.all(8),
          child: Text(
            ps.adsRemoved
                ? adsFreeLabel(context, ps.adsFreeUntil!)
                : '☕ Support the dev & remove ads',
            style: TextStyle(
              fontSize: 13,
              color: ps.adsRemoved ? Colors.greenAccent : Colors.white54,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white24,
              letterSpacing: 1,
            ),
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
