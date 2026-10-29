import 'dart:async';
import 'package:flutter/material.dart';
import 'android_family_links.dart';
import 'family_invite_link.dart';
import 'family_screen.dart';
import 'family_repository.dart';

class FamilyLinkHost extends StatefulWidget {
  const FamilyLinkHost({
    super.key,
    required this.child,
    required this.navigator,
    required this.messenger,
    required this.currentUid,
    this.repository,
  });
  final FamilyRepository? repository;
  final Widget child;
  final GlobalKey<NavigatorState> navigator;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final String? Function() currentUid;
  @override
  State<FamilyLinkHost> createState() => _FamilyLinkHostState();
}

class _FamilyLinkHostState extends State<FamilyLinkHost> {
  final _adapter = AndroidFamilyLinks();
  late final FamilyLinkRouter _router;
  @override
  void initState() {
    super.initState();
    _router = FamilyLinkRouter(
      currentUid: () => widget.currentUid(),
      canNavigate: () =>
          mounted &&
          widget.navigator.currentState != null &&
          !widget.navigator.currentState!.canPop(),
      notice: (message) {
        if (mounted) {
          widget.messenger.currentState?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
      open: (token) async {
        if (!mounted) return;
        await widget.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => FamilyScreen(
              initialInviteToken: token,
              repository: widget.repository,
            ),
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_adapter.start((raw) => unawaited(_router.receive(raw))));
      }
    });
  }

  @override
  void dispose() {
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
