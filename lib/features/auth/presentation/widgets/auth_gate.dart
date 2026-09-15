import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../home/presentation/screens/main_screen.dart';
import '../screens/login_screen.dart';
import '../../data/repositories/auth_repository.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.authRepository, this.mainBuilder});

  final AuthRepository? authRepository;
  final WidgetBuilder? mainBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream:
          authRepository?.authStateChanges() ??
          FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData &&
            !AuthRepository.requiresEmailVerification(snapshot.data)) {
          return mainBuilder?.call(context) ?? const MainScreen();
        }

        // No sign-out side effect in build: registration and login own it.
        return LoginScreen(authRepository: authRepository);
      },
    );
  }
}
