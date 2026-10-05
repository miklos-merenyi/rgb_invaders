# macOS: what's left before release

The Mac app builds and plays: J, K and L press the red, green and blue pads,
and there are no ads (AdMob has no macOS SDK). It uses the iOS bundle ID
`com.mermik.rgbinvaders`, so on App Store Connect it's the same app with a
macOS platform added, and the existing Game Center leaderboard and tip
products apply to it. Build commands are in COMMANDS.md, under "macOS".

## App and icon

- [ ] **App icon.** `macos/Runner/Assets.xcassets/AppIcon.appiconset` still
      holds Flutter's default icon. Generate the 16–1024 px sizes from
      `store_assets/app_store_icon_1024.png`. macOS doesn't round the corners
      for you, so give it the rounded-square shape with some transparent
      margin, the way other Mac icons are drawn.
- [ ] **App category.** Add `LSApplicationCategoryType` =
      `public.app-category.arcade-games` (or `games`) to
      `macos/Runner/Info.plist`. The Mac App Store rejects uploads without it.
- [ ] **Export compliance.** Copy `ITSAppUsesNonExemptEncryption` = `false`
      from `ios/Runner/Info.plist` into `macos/Runner/Info.plist`, so builds
      skip the export compliance question as the iOS ones do.
- [ ] **Signing team.** Set `DEVELOPMENT_TEAM = 4MN8W74K9M` for the Runner
      target in `macos/Runner.xcodeproj` (Xcode → Runner → Signing &
      Capabilities).
- [ ] **Start with the keyboard (optional).** Space or Return could press
      "Start Game"/"Play Again", so a game can be played without the mouse.

## Game Center

- [ ] Add the `com.apple.developer.game-center` entitlement (set to `true`)
      to `macos/Runner/Release.entitlements`, and to
      `DebugProfile.entitlements` once debug builds are signed with the team.
      Without it, sign-in fails on the Mac. It isn't there yet because an
      unsigned debug build with this entitlement won't launch.
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

The iOS release uses manual signing because of the accented name (see
COMMANDS.md, "App Store"). Do the same here.

- [ ] At developer.apple.com, create a **Mac App Store Connect** provisioning
      profile for `com.mermik.rgbinvaders` with the Apple Distribution
      certificate. Name it e.g. **`RGB Invaders Mac App Store`** and install
      it.
- [ ] Create a **Mac Installer Distribution** certificate (needed to sign the
      `.pkg` that gets uploaded) and add it to the keychain.
- [ ] Add `macos/ExportOptionsAppStore.plist`, like the iOS one but with the
      Mac profile's name and `installerSigningCertificate` =
      `3rd Party Mac Developer Installer`.
- [ ] **Release build fails.** `flutter build macos --release` stops at
      `release_unpack_macos` with "FlutterMacOS … does not contain
      architectures "arm64 x86_64"", even though `lipo` lists both. Debug
      builds work. Fix this (a newer Flutter, or a clean
      `~/Library/Developer/Xcode/DerivedData`) before archiving.
- [ ] Build, archive and upload:
      `flutter build macos --release`, then open
      `macos/Runner.xcworkspace` → Product → Archive → Distribute App → App
      Store Connect. Set `LANG`/`LC_ALL` as in COMMANDS.md. Once this works,
      add the exact steps to COMMANDS.md.
- [ ] Check the `.app` is universal (arm64 + x86_64) with
      `lipo -info "…/RGB Invaders.app/Contents/MacOS/RGB Invaders"`, unless
      the app is meant to be Apple silicon only.

## Store listing

- [x] **Screenshots.** Six 2880×1800 images are in
      `store_assets/screenshots/macos/`, made by
      `tool/make_mac_screenshots.py` (see COMMANDS.md, "macOS screenshots").
- [ ] **US screenshots (optional).** The captions say "colours"; for the US
      listing, change them to "colors" in the script and run it again.
- [ ] **Description.** `store_assets/app_store_description.txt` says "Tap Red,
      Green or Blue", mentions "multi-touch colour buttons" and "occasional
      ads". Write a Mac version that says J, K and L, and that the Mac app has
      no ads.
- [ ] **"Rate the app".** `_kAppStoreId` in `lib/game/game_screen.dart` is
      still empty. Once it's filled in, the Mac app opens the store's review
      page too.

## Sharing the app

- [ ] `lib/widgets/share_app.dart` says "Works on iPhone, iPad and Android."
      Add Mac.
- [ ] `get.html` shows Mac visitors the desktop view, which says "Scan with
      your phone". Consider sending them straight to the Mac App Store
      instead.
