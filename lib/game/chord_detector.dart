import 'dart:async';

/// Groups colour-button presses that land close together into one chord.
///
/// Same approach as rigobert's game screen: every pointer-down restarts a
/// short timer and snapshots the buttons held at that moment. When the timer
/// fires, that snapshot is the chord. Using the snapshot (rather than what is
/// held when the timer fires) means a finger lifting early inside the window
/// still counts, which is human imprecision rather than intent.
class ChordDetector {
  ChordDetector({
    required this.onChord,
    this.window = const Duration(milliseconds: 80),
  });

  /// Called with the OR-ed colour mask once a chord is complete.
  final void Function(int mask) onChord;

  final Duration window;

  /// Active pointers keyed by pointer id, valued by colour mask.
  final Map<int, int> _pointers = {};
  Timer? _timer;

  /// Colours currently held down.
  int get held => _pointers.values.fold(0, (a, b) => a | b);

  bool isHeld(int mask) => _pointers.containsValue(mask);

  void down(int pointer, int mask) {
    _pointers[pointer] = mask;
    _timer?.cancel();
    final snapshot = held;
    _timer = Timer(window, () => onChord(snapshot));
  }

  void up(int pointer) => _pointers.remove(pointer);

  /// Drops held pointers and any pending chord, e.g. when the game restarts.
  void reset() {
    _timer?.cancel();
    _pointers.clear();
  }

  void dispose() => _timer?.cancel();
}
