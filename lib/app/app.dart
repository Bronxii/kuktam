import 'package:flutter/material.dart';
import '../sharing/text_share_controller.dart';
import '../family/family_link_host.dart';

import 'package:kuktam/core/theme/app_colors.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/walkthrough/data/walkthrough_store.dart';
import 'package:kuktam/features/walkthrough/presentation/walkthrough_gate.dart';

class KuktamApp extends StatefulWidget {
  const KuktamApp({super.key, this.authRepository, this.walkthroughStore});

  final AuthRepository? authRepository;
  final WalkthroughStore? walkthroughStore;

  @override
  State<KuktamApp> createState() => _KuktamAppState();
}

class _KuktamAppState extends State<KuktamApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  String? _currentUid() {
    final user = (widget.authRepository ?? AuthRepository()).currentUser;
    return user != null && !AuthRepository.requiresEmailVerification(user)
        ? user.uid
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kuktám',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      builder: (context, child) => FamilyLinkHost(
        navigator: _navigator,
        messenger: _messenger,
        currentUid: _currentUid,
        child: child ?? const SizedBox.shrink(),
      ),
      navigatorObservers: [textShareNavigation],
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
      home: WalkthroughGate(
        store:
            widget.walkthroughStore ??
            const SharedPreferencesWalkthroughStore(),
        child: AuthGate(authRepository: widget.authRepository),
      ),
    );
  }
}
