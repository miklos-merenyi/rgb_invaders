# Circles

A small arcade game for Android and iOS, written in Flutter.

Invader-style monsters in seven colours fall from the top of the screen. Use
the **Red**, **Green** and **Blue** buttons to fire a circle that grows out from
the bottom of the screen:

- Tap one button to fire its colour.
- Press several buttons together (within 80 ms) to mix colours:
  R+G = yellow, G+B = cyan, R+B = magenta, R+G+B = white.
- A circle destroys the first monster of **its own colour** that it touches. It
  passes through monsters of other colours and disappears when it reaches the
  top.
- Only one circle can be on screen at a time.
- The game ends when a monster reaches the bottom. Monsters fall faster and
  appear more often as the game goes on.

## Running

```sh
flutter run            # on a connected device or simulator
flutter test           # game-logic tests
```

## Code

- `lib/game/game.dart`: game state and rules, with no Flutter widgets (easy to test)
- `lib/game/game_painter.dart`: draws the game on a canvas
- `lib/game/chord_detector.dart`: groups near-simultaneous presses into one colour (same approach as rigobert)
- `lib/game/color_pad.dart`: the glossy colour buttons and the colour-mix legend
- `lib/game/game_screen.dart`: game loop (Ticker), multi-touch buttons, overlays
