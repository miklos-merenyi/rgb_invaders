import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'chord_detector.dart';
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
    if (_game.phase == GamePhase.over && _game.overTime < 0.8) return;
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
                  if (_shownPhase != GamePhase.playing) _buildOverlay(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return SizedBox(
      height: 110,
      child: Row(
        children: [
          for (final mask in const [
            GameColors.red,
            GameColors.green,
            GameColors.blue,
          ])
            Expanded(child: _buildButton(mask)),
        ],
      ),
    );
  }

  Widget _buildButton(int mask) {
    final pressed = _chords.isHeld(mask);
    final color = GameColors.of(mask);
    return Listener(
      onPointerDown: (e) => _onButtonDown(e, mask),
      onPointerUp: _onButtonUp,
      onPointerCancel: _onButtonUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: pressed ? 0.95 : 0.55),
          borderRadius: BorderRadius.circular(18),
          boxShadow: pressed
              ? [BoxShadow(color: color, blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}
