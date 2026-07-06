import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const Invoice2IpsApp());
}

class Invoice2IpsApp extends StatelessWidget {
  const Invoice2IpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice2IPS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.stone50,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.emerald600,
          surface: Colors.white,
        ),
        splashFactory: InkRipple.splashFactory,
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: AppColors.emerald100,
          cursorColor: AppColors.emerald600,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
