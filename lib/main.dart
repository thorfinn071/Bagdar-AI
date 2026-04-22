import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Settings.instance.init();

  final startScreen = await resolveStartScreen();
  runApp(BagdarApp(home: startScreen));
}

class BagdarApp extends StatelessWidget {
  final Widget home;
  const BagdarApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bagdar AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.orangeAccent,
        ),
      ),
      home: home,
    );
  }
}
