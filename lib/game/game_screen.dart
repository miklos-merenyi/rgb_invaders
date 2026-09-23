import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/ad_service.dart';
import '../services/purchase_service.dart';
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
  late final Game _game = widget.game ?? Game();
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _clock = 0;
  GamePhase _shownPhase = GamePhase.ready;

  /// False between a game ending and its ad (if any) being dismissed, so the
  /// game-over screen can't be tapped away just as an ad appears.
  bool _overlayReady = true;

  /// Turns near-simultaneous button presses into one mixed colour.
  late final ChordDetector _chords = ChordDetector(onChord: _game.fire);

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
      if (_shownPhase == GamePhase.over) _afterGameOver();
    }
  }

  /// Counts the game, then shows an ad every [kAdEveryNGames] games, or the
  /// tip jar every [kTipPromptEvery] games, unless a tip removed ads.
  Future<void> _afterGameOver() async {
    setState(() => _overlayReady = false);
    // Let the player see what hit the bottom before anything pops up.
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final ps = PurchaseService();
    await ps.incrementGames();
    if (ps.shouldShowAd) await AdService().showIfReady();
    if (!mounted) return;
    setState(() => _overlayReady = true);
    if (ps.shouldShowTipPrompt) await showTipJar(context);
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
                  'A circle only destroys a monster of its own colour.',
                  textAlign: TextAlign.center,
                  style: body,
                ),
              const SizedBox(height: 32),
              const Text(
                'Tap to play',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 40),
              _buildSupportLink(),
            ],
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
