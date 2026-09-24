import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/ad_service.dart';
import '../services/leaderboard_service.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../widgets/tip_jar.dart';
import 'chord_detector.dart';
import 'color_pad.dart';
import 'game.dart';
import 'game_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.game});

  final Game? game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Game _game = (widget.game ?? Game())
    ..onHit = ((_) => _sounds.explosion())
    ..onMiss = _sounds.miss
    ..onWave = ((_) => _sounds.start());
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
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock += dt;
    _game.update(dt);
    _frame.value++;
    if (_game.phase != _shownPhase) {
      setState(() => _shownPhase = _game.phase);
      if (_shownPhase == GamePhase.over) {
        _sounds.gameOver();
        _afterGameOver();
      }
    }
  }

  /// Counts the game and submits its score, then shows an ad every
  /// [kAdEveryNGames] games, or the tip jar every [kTipPromptEvery] games,
  /// unless a tip removed ads. Otherwise a good enough score may offer
  /// leaderboard sign-in.
  Future<void> _afterGameOver() async {
    setState(() => _overlayReady = false);
    final score = _game.score;
    final lb = LeaderboardService();
    lb.submitScore(score);
    // Let the player see what hit the bottom before anything pops up.
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final ps = PurchaseService();
    await ps.incrementGames();
    if (ps.shouldShowAd) await AdService().showIfReady();
    if (!mounted) return;
    setState(() => _overlayReady = true);
    if (ps.shouldShowTipPrompt) {
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
    if (signIn == true && await lb.signIn()) await lb.submitScore(score);
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
    _sounds.start();
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
                  Positioned(top: 4, right: 4, child: _buildMuteButton()),
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
              Text(over ? 'GAME OVER' : 'CIRCLES', style: title),
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
                  'Every 30 monsters a new wave starts slower again,\n'
                  'but they come in pairs, then threes…',
                  textAlign: TextAlign.center,
                  style: body,
                ),
              const SizedBox(height: 32),
              const Text(
                'Tap to play',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 40),
              if (LeaderboardService().enabled) _buildLeaderboardLink(),
              _buildSupportLink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMuteButton() {
    return ListenableBuilder(
      listenable: _sounds,
      builder: (context, _) => IconButton(
        onPressed: _sounds.toggle,
        tooltip: _sounds.enabled ? 'Mute' : 'Unmute',
        icon: Icon(
          _sounds.enabled ? Icons.volume_up : Icons.volume_off,
          color: Colors.white38,
        ),
      ),
    );
  }

  Widget _buildLeaderboardLink() {
    return GestureDetector(
      onTap: _openLeaderboard,
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          '🏆 Leaderboard',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white54,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white24,
            letterSpacing: 1,
          ),
        ),
      ),
    );
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
