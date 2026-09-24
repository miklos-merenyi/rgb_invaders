# Commands

Run everything from the repo root. This Mac's shell has no UTF-8 locale, and
CocoaPods/Xcode tools crash on the team's accented name ("Miklós Merényi")
without it, so the iOS commands set `LANG`/`LC_ALL` explicitly.

## Dev

```sh
flutter run                      # connected device or emulator
flutter run -d emulator-5554     # a specific device (see `flutter devices`)
flutter analyze && flutter test
```

Install a debug build on every connected Android device:

```sh
flutter build apk --debug
adb devices | tail -n +2 | cut -sf 1 | xargs -I {} -P 4 \
    adb -s {} install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Store screenshots on the iPad simulator

App Store Connect wants 13-inch iPad screenshots (2064×2752), which is exactly
the iPad Pro 13-inch simulator. `DEMO=true` makes the game start and play
itself (see `_kDemo` in `lib/game/game_screen.dart`), since the simulator
can't be tapped from the command line.

`flutter build ios --simulator` fails here (Flutter's simulator engine is
arm64 only, but it asks for arm64 + x86_64), so it's only run to write the
dart-define into `ios/Flutter/Generated.xcconfig`; xcodebuild does the build.

```sh
SIM=$(xcrun simctl list devices available | grep 'iPad Pro 13-inch' | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $SIM; open -a Simulator
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ios --simulator --debug --dart-define=DEMO=true
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -configuration Debug -destination "id=$SIM" -derivedDataPath build/ios_sim_dd ONLY_ACTIVE_ARCH=YES build
xcrun simctl install $SIM build/ios_sim_dd/Build/Products/Debug-iphonesimulator/Runner.app
xcrun simctl launch $SIM com.mermik.rgbinvaders
xcrun simctl io $SIM screenshot shot.png     # repeat at good moments
```

Simulator screenshots have an alpha channel, which App Store Connect rejects:

```sh
python3 -c "import sys; from PIL import Image; [Image.open(f).convert('RGB').save(f) for f in sys.argv[1:]]" shot*.png
```

Drop `--dart-define=DEMO=true` (and rebuild) for a normal simulator build.

## Before every release

Bump the build number in `pubspec.yaml` (`version: 1.0.0+N`). Both stores
reject a build number they've already seen. Change the `1.0.0` part only for a
new public version.

## Google Play

Needs `android/key.properties` and the upload keystore (see README, "Release
signing").

```sh
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab, upload in Play Console
```

## App Store

### One-time setup

The release build uses manual signing. Xcode's automatic (cloud-managed)
distribution signing produces an "Invalid Signature" for this team because of
the accented name; see rigobert's `IOS_RELEASE.md` for the full story.

1. The local **Apple Distribution: Miklós Merényi (4MN8W74K9M)** certificate
   is already in the keychain (shared with rigobert). Check with
   `security find-identity -v -p codesigning`.
2. At developer.apple.com → Profiles → **+** → **App Store Connect**, pick the
   App ID `com.mermik.rgbinvaders` and that certificate, and name the profile
   exactly **`RGB Invaders App Store`** (the name
   `ios/ExportOptionsAppStore.plist` refers to). Download it and double-click
   it to install.
3. The App ID needs **Game Center** and **In-App Purchase** enabled. If you
   change capabilities later, regenerate the profile.

### Build, check, upload

```sh
# 0. Only if you ran on the Simulator since the last device build: native-assets
#    caching doesn't reliably switch between Simulator and device.
flutter clean
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*

# 1. Archive and export the signed .ipa
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ipa --release \
    --export-options-plist=ios/ExportOptionsAppStore.plist

# 2. Add the dSYMs Xcode doesn't make (the prebuilt AdMob frameworks, and
#    anything else without one), since App Store Connect flags missing UUIDs.
#    The build also leaves a duplicate "objective_c.framework 1.dSYM"; drop it.
ARCHIVE=build/ios/archive/Runner.xcarchive
APP="$ARCHIVE/Products/Applications/Runner.app"
find "$ARCHIVE/dSYMs" -maxdepth 1 -name '* [0-9].dSYM' -exec rm -rf {} +
for FW_DIR in "$APP"/Frameworks/*.framework; do
    FW=$(basename "$FW_DIR" .framework)
    [ -d "$ARCHIVE/dSYMs/$FW.framework.dSYM" ] && continue
    BIN="$FW_DIR/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$FW_DIR/Info.plist")"
    dsymutil -o "$ARCHIVE/dSYMs/$FW.framework.dSYM" "$BIN" 2>/dev/null \
        && echo "dSYM added: $FW"
done

# 3. Verify: both must say arm64, and codesign must say
#    "satisfies its Designated Requirement"
lipo -info "$APP/Runner"
lipo -info "$APP/Frameworks/objective_c.framework/objective_c"
rm -rf /tmp/ipa-check && mkdir /tmp/ipa-check && \
    unzip -q build/ios/ipa/*.ipa -d /tmp/ipa-check && \
    codesign --verify --deep --strict --verbose=4 /tmp/ipa-check/Payload/Runner.app

# 4. Show the archive in Xcode Organizer (it only looks in this folder), then
#    Organizer → Distribute App → App Store Connect → Upload.
DATE_DIR=~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)
mkdir -p "$DATE_DIR"
find "$DATE_DIR" -maxdepth 1 -name 'RGB Invaders*.xcarchive' -exec rm -rf {} +
cp -R "$ARCHIVE" "$DATE_DIR/RGB Invaders $(date '+%-m-%-d-%y, %-I.%M %p').xcarchive"
```

Instead of step 4 you can drag `build/ios/ipa/*.ipa` into Apple's
**Transporter** app. That uploads the .ipa but not the dSYMs added in step 2,
so prefer Organizer.

After the upload is processed (usually 10–30 minutes), the build appears in
App Store Connect under TestFlight and can be attached to a version.
