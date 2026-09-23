import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_screen.dart';
import 'services/ad_service.dart';
import 'services/purchase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await PurchaseService().init();
  await AdService().init();
  runApp(const CirclesApp());
}

class CirclesApp extends StatelessWidget {
  const CirclesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const GameScreen(),
    );
  }
}
