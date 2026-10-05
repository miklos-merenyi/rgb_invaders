import 'package:flutter/foundation.dart';

// Where the app runs. Based on defaultTargetPlatform rather than dart:io's
// Platform, which throws in a browser, so widget tests can pick a platform.
// In a browser, defaultTargetPlatform is the visitor's OS, hence the kIsWeb
// checks.

bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Game Center and the App Store rather than Play Games and Google Play.
bool get isApple => isIOS || isMacOS;

/// True in the store apps, which have tips, ratings and leaderboards. The
/// web version has none of these.
bool get hasStore => !kIsWeb;

/// Played with the J, K and L keys, so the pads show their keys: the Mac
/// app, and the web version on a computer.
bool get playsWithKeys =>
    isMacOS ||
    kIsWeb &&
        switch (defaultTargetPlatform) {
          TargetPlatform.android || TargetPlatform.iOS => false,
          _ => true,
        };
