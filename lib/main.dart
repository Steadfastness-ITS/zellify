import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_colors.dart';
import 'features/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Let the app draw behind the phone's status bar (the green header does this).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ZellifyApp());
}

class ZellifyApp extends StatelessWidget {
  const ZellifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zellify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.pageBg,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
      ),
      home: const HomeScreen(),
    );
  }
}
