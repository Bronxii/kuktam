import 'dart:async';
import 'package:flutter/material.dart';
import 'android_family_links.dart';
import 'family_invite_link.dart';
import 'family_screen.dart';
import 'family_repository.dart';
import 'pending_family_invite.dart';
import '../sharing/text_share_controller.dart';

class FamilyLinkHost extends StatefulWidget {
  const FamilyLinkHost({
    super.key,
    required this.child,
    required this.navigator,
    required this.messenger,
    required this.currentUid,
    this.repository,
    this.pendingStore,
  });
  final FamilyRepository? repository;
  final PendingFamilyInviteStore? pendingStore;
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
  String? _admittedUid;
  void _admit(String? uid) {
    _admittedUid = uid;
    if (uid != null) unawaited(_router.resume());
  }

  void _navigationChanged() => unawaited(_router.resume());
  @override
  void initState() {
    super.initState();
    _router = FamilyLinkRouter(
      pendingStore: widget.pendingStore ?? SecurePendingFamilyInviteStore(),
      currentUid: () =>
          _admittedUid != null && _admittedUid == widget.currentUid()
          ? _admittedUid
          : null,
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
    textShareNavigation.changes.addListener(_navigationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _router.restore();
      if (!mounted) return;
      await _adapter.start((raw) => unawaited(_router.receive(raw)));
      if (mounted) await _router.resume();
    });
  }

  @override
  void dispose() {
    textShareNavigation.changes.removeListener(_navigationChanged);
    _adapter.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FamilyInviteAdmissionScope(
    admit: _admit,
    child: ListenableBuilder(
      listenable: _router,
      builder: (_, _) => Column(
        children: [
          if (_router.hasPending || _router.storageError != null)
            Material(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _router.storageError ??
                            'Családi meghívó vár rád. Bejelentkezés után folytatjuk.',
                      ),
                      TextButton(
                        onPressed: () => unawaited(_router.cancelPending()),
                        child: const Text('Meghívó elvetése'),
                      ),
                      if (_router.storageError != null)
                        TextButton(
                          onPressed: () async {
                            await _router.retryPending();
                            await _router.resume();
                          },
                          child: const Text('Újrapróbálás'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: widget.child),
        ],
      ),
    ),
  );
}

/// Signals admission from INSIDE existing walkthrough/auth/household gates.
class FamilyInviteAdmissionScope extends InheritedWidget {
  const FamilyInviteAdmissionScope({
    super.key,
    required this.admit,
    required super.child,
  });
  final void Function(String?) admit;
  @override
  bool updateShouldNotify(FamilyInviteAdmissionScope oldWidget) => false;
}

class FamilyInviteAdmission extends StatefulWidget {
  const FamilyInviteAdmission({
    super.key,
    required this.uid,
    required this.child,
  });
  final String uid;
  final Widget child;
  @override
  State<FamilyInviteAdmission> createState() => _FamilyInviteAdmissionState();
}

class _FamilyInviteAdmissionState extends State<FamilyInviteAdmission> {
  void Function(String?)? _admit;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _admit = context
        .dependOnInheritedWidgetOfExactType<FamilyInviteAdmissionScope>()
        ?.admit;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _admit?.call(widget.uid);
    });
  }

  @override
  void dispose() {
    _admit?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
