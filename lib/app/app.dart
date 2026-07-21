import 'package:flutter/material.dart';

import 'package:kuktam/core/theme/app_colors.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';

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
      home: const AuthGate(),
    );
  }
}