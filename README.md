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

## Ads and tipping

Set up the same way as rigobert:

- An interstitial ad is shown after every 5th game (`kAdEveryNGames`).
- Every 20th game shows the tip jar instead of the ad (`kTipPromptEvery`).
  The tip jar can also be opened any time from the start and game-over screens.
- A tip removes ads for a while: small = 1 month, medium = 3 months,
  royal = 1 year. Tips stack, and the time is stored on the device.
- Ads are limited to G-rated content for children.

Before a release:

1. Create the Circles app in [AdMob](https://admob.google.com) with one
   interstitial unit per platform. Put the app IDs in
   `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`,
   which currently hold Google's test IDs. Put the unit IDs in
   `lib/services/ad_service.dart`. Release builds show no ads until this is done.
2. Create three consumable in-app products:
   - App Store Connect: `com.mermik.circles.tip_small`, `…tip_medium`,
     `…tip_large`
   - Play Console: `tip_small`, `tip_medium`, `tip_large`

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
- `lib/services/`: ads (`ad_service.dart`) and tips / ad-free time (`purchase_service.dart`)
- `lib/widgets/tip_jar.dart`: the tip jar dialog
