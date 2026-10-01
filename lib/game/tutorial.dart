import 'game.dart';

/// One lesson of the tutorial: what to tell the player, and the invaders
/// (or boss) to drop in for them to shoot.
class TutorialStep {
  const TutorialStep(this.text, [this.setup, this.done, this.praise]);

  /// Colour names in capitals (RED, YELLOW, ...) are shown in their colour.
  final String text;

  /// Fills the field for this step; null for the closing card, which has
  /// nothing to shoot.
  final void Function(Game game)? setup;

  /// True once the player has done enough; by default once every invader
  /// and the boss are gone. What's left is then cleared away.
  final bool Function(Game game)? done;

  /// Shown in place of [text] between [done] and the next step.
  final String? praise;
}

/// Walks the player through the game in a [Game.practice] round, a step at a
/// time: each step's invaders (or the first few bands of its boss) must be
/// shot before the next begins.
class Tutorial {
  Tutorial(this.game);

  final Game game;

  /// Pause after a step's last hit, so its explosion plays out before the
  /// next instructions appear.
  static const double stepPause = 1.0;

  /// Longer pause for a step with [TutorialStep.praise], to read it.
  static const double praisePause = 2.0;

  /// Boss bands to shoot before the tutorial calls it a day.
  static const int bossBands = 3;

  static final steps = [
    TutorialStep(
      'Tap RED to fire a ring of colour.\n'
      'It destroys invaders of its own colour.',
      (g) => g.dropMonster(GameColors.red),
    ),
    TutorialStep(
      'Now shoot the GREEN one.',
      (g) => g.dropMonster(GameColors.green),
    ),
    TutorialStep('And the BLUE one.', (g) => g.dropMonster(GameColors.blue)),
    TutorialStep(
      'A ring passes straight through other colours,\n'
      'and only one ring flies at a time. Shoot both!',
      (g) => g
        ..dropMonster(GameColors.blue, x: 0.3)
        ..dropMonster(GameColors.red, x: 0.7),
    ),
    TutorialStep(
      'Press RED and GREEN together to mix YELLOW.',
      (g) => g.dropMonster(GameColors.red | GameColors.green),
    ),
    TutorialStep(
      'GREEN and BLUE make CYAN.',
      (g) => g.dropMonster(GameColors.green | GameColors.blue),
    ),
    TutorialStep(
      'RED and BLUE make MAGENTA.',
      (g) => g.dropMonster(GameColors.red | GameColors.blue),
    ),
    TutorialStep(
      'All three together make WHITE.\n'
      'Mixed colours score more: 1 point per button.',
      (g) => g.dropMonster(7),
    ),
    TutorialStep(
      'Between waves a boss comes down.\n'
          'Only its lowest colour hurts it: shoot it away band by band.\n'
          'A wrong colour pushes it closer!',
      // Every colour once, plus yellow again, no twins side by side.
      (g) => g.dropBoss(const [5, 2, 7, 3, 6, 1, 4, 3]),
      (g) => (g.boss?.alive ?? 0) <= Boss.bandCount - bossBands,
      "You've got it!",
    ),
    const TutorialStep(
      'Hit 5 of one colour in a row for TURBO,\n'
      'then 5 more in a row to clear the whole screen!\n\n'
      'Waves get faster and bigger as you go.\n'
      "Don't let a single invader reach the bottom.",
    ),
  ];

  int step = 0;

  /// Seconds since the current step was done, or null while it isn't.
  double? _doneFor;

  TutorialStep get current => steps[step];

  /// What to tell the player right now.
  String get text =>
      _doneFor != null ? current.praise ?? current.text : current.text;

  /// True on the closing card.
  bool get finished => current.setup == null;

  /// Starts a practice round on the first step.
  void begin() {
    game.startPractice();
    step = 0;
    _doneFor = null;
    current.setup?.call(game);
  }

  /// Moves on a moment after the current step is done. Returns true when
  /// what to show changed: praise appeared or the next step began.
  bool update(double dt) {
    if (finished) return false;
    final doneFor = _doneFor;
    if (doneFor == null) {
      final done =
          current.done?.call(game) ??
          (game.monsters.isEmpty && game.boss == null);
      if (!done) return false;
      game.monsters.clear();
      game.dismissBoss();
      _doneFor = 0;
      return current.praise != null;
    }
    _doneFor = doneFor + dt;
    if (_doneFor! < (current.praise == null ? stepPause : praisePause)) {
      return false;
    }
    _doneFor = null;
    step++;
    current.setup?.call(game);
    return true;
  }
}
