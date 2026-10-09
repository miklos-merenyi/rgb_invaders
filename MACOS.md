# macOS: what's left before release

The Mac app builds and plays: J, K and L press the red, green and blue pads,
and there are no ads (AdMob has no macOS SDK). It uses the iOS bundle ID
`com.mermik.rgbinvaders`, so on App Store Connect it's the same app with a
macOS platform added, and the existing Game Center leaderboard and tip
products apply to it. Build commands are in COMMANDS.md, under "macOS".

## App and icon

- [x] **App icon.** `tool/make_icons.py` draws the 16–1024 px sizes as a
      rounded square with a shadow on Apple's Mac icon grid.
- [x] **App category.** `LSApplicationCategoryType` =
      `public.app-category.arcade-games` is in `macos/Runner/Info.plist`.
- [x] **Export compliance.** `ITSAppUsesNonExemptEncryption` = `false` is in
      `macos/Runner/Info.plist`.
- [x] **Signing team.** `DEVELOPMENT_TEAM = 4MN8W74K9M` is set for the Runner
      target. Debug builds are still signed ad hoc, so `flutter run` works
      without a profile.
- [x] **Start with the keyboard.** Return (or Enter on the number pad)
      presses "Start Game"/"Play Again", so a game can be played without the
      mouse.

## Game Center

- [x] `macos/Runner/Release.entitlements` has
      `com.apple.developer.game-center`. `DebugProfile.entitlements` doesn't,
      because an ad hoc signed build with it won't launch, so Game Center
      only works in builds signed with the team.
- [ ] Check that sign-in, score submission and the leaderboard sheet work in
      a signed build. The leaderboard ID is the iOS one,
      `com.mermik.rgbinvaders.highscores`.

## Tips (in-app purchase)

- [ ] In App Store Connect, add the macOS platform to the existing RGB
      Invaders app record (App Information → **+** next to the platform).
      Because the bundle ID is the same, the iOS tip products
      (`com.mermik.rgbinvaders.tip_small` / `_medium` / `_large`) apply to the
      Mac app too.
- [ ] Test a tip with a sandbox account. On the Mac, a tip gives time
      without tip-jar popups (there are no ads to remove), and the tip jar
      says so.

## Signing and upload

The Release configuration is signed manually with Apple Distribution and the
`RGB Invaders macos` profile. The Game Center entitlement needs a real
signature, and automatic signing would need this Mac registered as a device.
So a release build needs the profile installed, and the release `.app` only
runs once installed from the store (or TestFlight).

- [x] The **Mac App Store Connect** profile `RGB Invaders macos` (Apple
      Distribution certificate, Game Center) is installed; see COMMANDS.md.
- [x] The **3rd Party Mac Developer Installer** certificate (signs the
      `.pkg` that gets uploaded) is in the keychain.
- [x] `macos/ExportOptionsAppStore.plist` exists.
- [x] **Release build fixed.** Flutter 3.47.5 works with Xcode 27's `lipo`;
      the app is universal (arm64 + x86_64).
- [x] Archive and export, following COMMANDS.md ("Mac App Store"). This
      makes a signed, universal `RGB Invaders.pkg`.
- [ ] Upload the `.pkg` and check it's processed in App Store Connect.

## Store listing

- [x] **Screenshots.** Six 2880×1800 images are in
      `store_assets/screenshots/macos/`, made by
      `tool/make_mac_screenshots.py` (see COMMANDS.md, "macOS screenshots").
- [ ] **US screenshots (optional).** The captions say "colours"; for the US
      listing, change them to "colors" in the script and run it again.
- [x] **Description.** `store_assets/mac_app_store_description.txt` has
      the Mac promotional text, keywords and description: J, K and L instead
      of taps, and no ads.
- [ ] **"Rate the app".** `_kAppStoreId` in `lib/game/game_screen.dart` is
      still empty. Once it's filled in, the Mac app opens the store's review
      page too.

## Sharing the app

- [ ] `lib/widgets/share_app.dart` says "Works on iPhone, iPad and Android."
      Add Mac.
- [ ] `get.html` shows Mac visitors the desktop view, which says "Scan with
      your phone". Consider sending them straight to the Mac App Store
      instead.
