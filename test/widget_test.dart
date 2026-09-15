import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/app/app.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'auth/email_verification_test.dart' show TestAuth, TestUser;
import 'walkthrough/walkthrough_test.dart' show MemoryStore;

void main() {
  testWidgets('Kuktám alkalmazás elindul', (WidgetTester tester) async {
    final auth = TestAuth(TestUser(true, ['password']));
    await tester.pumpWidget(
      KuktamApp(
        authRepository: AuthRepository(firebaseAuth: auth),
        walkthroughStore: MemoryStore()..completed = true,
      ),
    );
    await tester.pump();
    auth.changes.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Kuktám'), findsOneWidget);
    expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
    await auth.changes.close();
  });
}
