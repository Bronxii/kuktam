import 'package:flutter/material.dart';

import '../data/walkthrough_store.dart';
import 'walkthrough_screen.dart';

class WalkthroughGate extends StatefulWidget {
  const WalkthroughGate({super.key, required this.store, required this.child});

  final WalkthroughStore store;
  final Widget child;

  @override
  State<WalkthroughGate> createState() => _WalkthroughGateState();
}

class _WalkthroughGateState extends State<WalkthroughGate> {
  bool? _completed;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var completed = false;
    try {
      completed = await widget.store.isCompleted();
    } catch (_) {
      // Missing/unreadable local state always shows the introduction.
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _finish() async {
    if (_saving || _completed == true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.complete();
      if (mounted) setState(() => _completed = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Nem sikerült elmenteni a bemutató befejezését. Próbáld újra.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_completed!) return widget.child;
    return WalkthroughScreen(onFinish: _finish, saving: _saving, error: _error);
  }
}
