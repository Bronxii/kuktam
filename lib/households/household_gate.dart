import 'package:flutter/material.dart';
import 'household_gateway.dart';
import 'production_household_context.dart';

/// Session-keyed by AuthGate. Neither recipes nor shopping are needed to join
/// this gate; Free users receive the same account foundation as Pro users.
class HouseholdGate extends StatefulWidget {
  const HouseholdGate({super.key, required this.child, this.gateway});
  final Widget child;
  final HouseholdGateway? gateway;
  @override
  State<HouseholdGate> createState() => _HouseholdGateState();
}

class _HouseholdGateState extends State<HouseholdGate> {
  late final gateway = widget.gateway ?? productionHouseholdContext();
  Stream<String> _watch() => gateway is ObservableHouseholdGateway
      ? (gateway as ObservableHouseholdGateway).watch()
      : gateway.ensure().asStream();
  late Stream<String> ready = _watch();
  @override
  Widget build(BuildContext context) => StreamBuilder<String>(
    stream: ready,
    builder: (context, snapshot) {
      if (snapshot.hasData && !snapshot.hasError) return widget.child;
      return Scaffold(
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'A fiók előkészítéséhez internetkapcsolat szükséges. Ellenőrizd a kapcsolatot, majd próbáld újra.',
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        ready = _watch();
                      }),
                      child: const Text('Újrapróbálás'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
