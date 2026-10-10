import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/export/presentation/recipe_export_screen.dart';
import 'package:kuktam/export/presentation/recipe_export_controller.dart';
import 'export_test.dart' show SessionFixture, Port, Files, controller;

void main() {
  testWidgets('export error and retry recover without automatic handoff', (
    tester,
  ) async {
    final s = SessionFixture();
    final p = Port()..error = Exception();
    final f = Files();
    final c = controller(s, p, f);
    await tester.pumpWidget(
      MaterialApp(home: RecipeExportScreen(createController: () => c)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mentés'), findsNothing);
    expect(find.text('Újra'), findsOneWidget);
    p.error = null;
    await tester.tap(find.text('Újra'));
    await tester.pumpAndSettle();
    expect(find.text('Mentés'), findsOneWidget);
    expect(f.shares, 0);
    expect(f.saves, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(f.discards, 1);
  });
  test(
    'ready artifact cannot be saved or shared after session change',
    () async {
      final s = SessionFixture();
      final f = Files();
      final c = controller(s, Port(), f);
      addTearDown(c.dispose);
      await c.start();
      s.change('b');
      s.change('a');
      await c.save();
      await c.share();
      expect(f.saves, 0);
      expect(f.shares, 0);
      expect(c.message, contains('fiók'));
    },
  );
  test(
    'closing during build then reopening cannot start a second snapshot',
    () async {
      final p = Port()..wait = Completer<void>();
      final c = controller(SessionFixture(), p, Files());
      final first = c.start();
      c.dispose();
      final p2 = Port();
      final c2 = controller(SessionFixture(), p2, Files());
      addTearDown(c2.dispose);
      await c2.start();
      expect(p2.calls, isEmpty);
      expect(c2.phase, ExportPhase.failed);
      p.wait!.complete();
      await first;
      await c2.start();
      expect(c2.phase, ExportPhase.ready);
    },
  );
}
