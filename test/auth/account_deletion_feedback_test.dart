import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/features/auth/data/repositories/account_deletion_gateway.dart';
import 'package:kuktam/features/auth/presentation/widgets/account_deletion_dialog.dart';
import 'account_deletion_test.dart' show Fixture;
import 'account_deletion_coordination_test.dart' show Gateway, modern;

void main() {
  for (final outcome in DeletionCompletion.values) {
    testWidgets('accepted deletion feedback: $outcome', (tester) async {
      final f = Fixture(['google.com']);
      final g = Gateway()..onFinalize = () async => outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => AccountDeletionDialog(repository: modern(f, g)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
      await tester.pumpAndSettle();
      expect(g.begins, 1);
      expect(g.finalizes, 1);
      expect(f.user.deletes, 0);
      expect(f.auth.currentUser, isNull);
      expect(find.widgetWithText(FilledButton, 'Fiók törlése'), findsNothing);
      if (outcome == DeletionCompletion.completed) {
        expect(find.byType(AccountDeletionDialog), findsNothing);
      } else {
        expect(find.text('Rendben'), findsOneWidget);
        expect(
          find.textContaining(
            outcome == DeletionCompletion.supportRequired
                ? 'segítség szükséges'
                : 'automatikusan befejeződik',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('próbáld újra'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Rendben'), findsOneWidget);
      }
    });
  }
  testWidgets('begin failure remains retryable and keeps session', (
    tester,
  ) async {
    final f = Fixture(['google.com']);
    final g = Gateway()
      ..onBegin = () async {
        throw StateError('offline');
      };
    await tester.pumpWidget(
      MaterialApp(home: AccountDeletionDialog(repository: modern(f, g))),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pumpAndSettle();
    expect(find.textContaining('próbáld újra'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fiók törlése'), findsOneWidget);
    expect(f.auth.currentUser, f.user);
    expect(f.db.deleted, isEmpty);
    expect(g.finalizes, 0);
  });
}
