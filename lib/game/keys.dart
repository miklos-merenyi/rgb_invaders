import 'package:flutter/services.dart';

import 'game.dart';

/// The keyboard keys that press the colour buttons, for the Mac app (and any
/// device with a keyboard attached).
final kColourKeys = {
  LogicalKeyboardKey.keyJ: GameColors.red,
  LogicalKeyboardKey.keyK: GameColors.green,
  LogicalKeyboardKey.keyL: GameColors.blue,
};

/// The key for each colour button, by its mask.
final kKeyLabels = {
  for (final MapEntry(key: key, value: mask) in kColourKeys.entries)
    mask: key.keyLabel,
};
