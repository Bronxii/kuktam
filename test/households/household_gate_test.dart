import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/households/household_gateway.dart';
import 'package:kuktam/households/household_gate.dart';

class Gateway implements HouseholdGateway {
  Completer<String> pending = Completer<String>();
  int calls = 0;
  @override
  Future<String> ensure() {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'normal Free content waits for authoritative household; rerender does not duplicate ensure',
    (tester) async {
      final gateway = Gateway();
      Widget app() => MaterialApp(
        home: HouseholdGate(
          gateway: gateway,
          child: const Text('Recipes and shopping'),
        ),
      );
      await tester.pumpWidget(app());
      expect(gateway.calls, 1);
      expect(find.text('Recipes and shopping'), findsNothing);
      await tester.pumpWidget(app());
      expect(gateway.calls, 1);
      gateway.pending.complete('home');
      await tester.pump();
      expect(find.text('Recipes and shopping'), findsOneWidget);
    },
  );
  testWidgets(
    'interrupted initialization exposes retry and never opens content prematurely',
    (tester) async {
      final gateway = Gateway();
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdGate(gateway: gateway, child: const Text('Content')),
        ),
      );
      gateway.pending.completeError(StateError('offline'));
      await tester.pump();
      expect(find.text('Content'), findsNothing);
      gateway.pending = Completer<String>();
      await tester.tap(find.text('Újrapróbálás'));
      await tester.pump();
      expect(gateway.calls, 2);
      gateway.pending.complete('home');
      await tester.pump();
      expect(find.text('Content'), findsOneWidget);
    },
  );
  testWidgets(
    'keyed session replacement cannot show earlier account after delayed initialization',
    (tester) async {
      final a = Gateway(), b = Gateway();
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdGate(
            key: const ValueKey('a'),
            gateway: a,
            child: const Text('A'),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdGate(
            key: const ValueKey('b'),
            gateway: b,
            child: const Text('B'),
          ),
        ),
      );
      a.pending.complete('a-home');
      await tester.pump();
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
      b.pending.complete('b-home');
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
    },
  );
}
