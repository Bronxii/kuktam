import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/app/app.dart';

void main() {
  testWidgets('Kuktám alkalmazás elindul', (WidgetTester tester) async {
    await tester.pumpWidget(const KuktamApp());

    expect(find.text('Kuktám'), findsOneWidget);
    expect(find.text('Bejelentkezés'), findsOneWidget);
  });
}