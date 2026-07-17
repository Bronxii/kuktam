import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../features/auth/presentation/screens/login_screen.dart';

class KuktamApp extends StatelessWidget {
  const KuktamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kuktám',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.forestGreen,
          primary: AppColors.forestGreen,
          secondary: AppColors.orange,
          surface: AppColors.cream,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}