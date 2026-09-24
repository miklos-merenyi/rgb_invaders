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
  await AdService().init();
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
