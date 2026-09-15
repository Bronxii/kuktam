import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../home/presentation/screens/main_screen.dart';
import '../screens/login_screen.dart';
import '../../data/repositories/auth_repository.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authRepository, this.mainBuilder});
  final AuthRepository? authRepository;
  final WidgetBuilder? mainBuilder;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthRepository _repository;
  late final Stream<User?> _users;
  bool _firstEvent = true;
  bool _restoredVerificationRequired = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.authRepository ?? AuthRepository();
    _users = _repository.authStateChanges().asyncMap((user) async {
      final first = _firstEvent;
      _firstEvent = false;
      if (user != null && !AuthRepository.requiresEmailVerification(user)) {
        _restoredVerificationRequired = false;
      }
      // Only restored sessions: registration/login own their temporary sessions.
      if (first && AuthRepository.requiresEmailVerification(user)) {
        _restoredVerificationRequired = true;
        try {
          await _repository.signOutUnverifiedSession();
        } catch (_) {
          // Fail closed without repeatedly signing out from widget rebuilds.
        }
      }
      return user;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _users,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null && !AuthRepository.requiresEmailVerification(user)) {
          return KeyedSubtree(
            key: ValueKey(user.uid),
            child: widget.mainBuilder?.call(context) ?? const MainScreen(),
          );
        }
        return LoginScreen(
          authRepository: _repository,
          verificationRequired: _restoredVerificationRequired,
        );
      },
    );
  }
}
