import 'dart:async';
import 'package:flutter/widgets.dart';
import '../monetization/monetization_coordinator.dart';
import 'pro_controller.dart';

/// App-owned composition above Navigator. Routes only borrow the controller.
class MonetizationHost extends StatefulWidget {
  const MonetizationHost({
    super.key,
    required this.coordinator,
    required this.userIds,
    required this.child,
  });
  final MonetizationCoordinator coordinator;
  final Stream<String?> userIds;
  final Widget child;
  @override
  State<MonetizationHost> createState() => _MonetizationHostState();
}

class _MonetizationHostState extends State<MonetizationHost>
    with WidgetsBindingObserver {
  late final ProController controller;
  late final StreamSubscription<String?> subscription;
  @override
  void initState() {
    super.initState();
    controller = ProController(
      entitlements: widget.coordinator.entitlements,
      purchases: widget.coordinator.purchases,
      paymentsEnabled: widget.coordinator.onlineEnabled,
    );
    subscription = widget.userIds.distinct().listen(
      (uid) {
        unawaited(widget.coordinator.changeSession(uid));
      },
      onError: (Object _) {
        unawaited(widget.coordinator.changeSession(null));
      },
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.coordinator.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(subscription.cancel());
    controller.dispose();
    unawaited(widget.coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ProScope(controller: controller, child: widget.child);
}

class ProScope extends InheritedNotifier<ProController> {
  const ProScope({
    super.key,
    required ProController controller,
    required super.child,
  }) : super(notifier: controller);
  static ProController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProScope>()?.notifier;
}
