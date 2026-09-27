import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_screen.dart';
import 'services/ad_service.dart';
import 'services/leaderboard_service.dart';
import 'services/purchase_service.dart';
import 'services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await PurchaseService().init();
  // Not awaited: the ads SDK's start-up is slow on older phones and no ad
  // is needed before the first game over.
  unawaited(
    AdService().init().catchError(
      (Object e) => debugPrint('[AdService] init failed: $e'),
    ),
  );
  await SoundService().init();
  await LeaderboardService().init();
  runApp(const RgbInvadersApp());
}

class RgbInvadersApp extends StatelessWidget {
  const RgbInvadersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RGB Invaders',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const GameScreen(),
    );
  }
}
