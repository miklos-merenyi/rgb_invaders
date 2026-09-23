import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
