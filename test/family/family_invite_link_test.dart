import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/family/callable_family_repository.dart';
import 'package:kuktam/family/family_mutation.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/family/family_state.dart';
import 'fakes.dart';
import 'family_mutation_test.dart' show Mutations;
import 'family_test.dart' show response;

String get token => 'A' * 43;
String get url => 'https://kuktam-67768.web.app/family/invite?token=$token';
Map<String, Object?> payload() => {
  'schemaVersion': 1,
  'inviteId': 'a' * 64,
  'token': token,
  'inviteUrl': url,
  'expiresAt': 1800000000000,
};
void main() {
  test(
    '8A exact server link retained no client reconstruction or extra calls',
    () async {
      final auth = TestAuth(), functions = Functions();
      addTearDown(auth.events.close);
      functions.callable.reply = () async => payload();
      final r = await CallableFamilyRepository(
        auth: auth,
        functions: functions,
      ).createInvite();
      expect(r.inviteUrl, url);
      expect(r.code, token);
      expect(functions.names, ['createFamilyInvite']);
      expect(functions.callable.sent, [{}]);
    },
  );
  for (final kind in [
    'missing',
    'malformed',
    'http',
    'host',
    'port',
    'userinfo',
    'path',
    'slash',
    'extra',
    'duplicate',
    'wrongToken',
    'fragment',
    'encoded',
    'whitespace',
  ]) {
    test('8A invalid URL $kind safely rejected', () {
      final raw = payload();
      raw['inviteUrl'] = switch (kind) {
        'missing' => null,
        'malformed' => 'not a URL',
        'http' => url.replaceFirst('https:', 'http:'),
        'host' => url.replaceFirst('kuktam-67768.web.app', 'untrusted.example'),
        'port' => url.replaceFirst('.app/', '.app:443/'),
        'userinfo' => url.replaceFirst('https://', 'https://user@'),
        'path' => url.replaceFirst('/family/invite', '/other'),
        'slash' => url.replaceFirst('?', '/?'),
        'extra' => '$url&uid=secret',
        'duplicate' => '$url&token=$token',
        'wrongToken' => url.replaceFirst('token=A', 'token=B'),
        'fragment' => '$url#fragment',
        'encoded' => url.replaceFirst('token=A', 'token=%41'),
        _ => ' $url',
      };
      expect(
        () => FamilyInviteResult.fromResponse(raw),
        throwsA(isA<FamilyMutationException>()),
      );
    });
  }
  testWidgets(
    '8A owner sees link and manual code copies each exact credential',
    (t) async {
      final r = Mutations()
        ..reply = () async => FamilyState.fromResponse(response(), 'a');
      r.invite = () async => FamilyInviteResult.fromResponse(payload());
      addTearDown(r.events.close);
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: r)));
      await t.pumpAndSettle();
      await t.tap(find.text('Tag meghívása'));
      await t.pumpAndSettle();
      expect(find.text(url), findsOneWidget);
      expect(find.text(token), findsOneWidget);
      await t.ensureVisible(find.text('Link másolása'));
      await t.tap(find.text('Link másolása'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Kód másolása'));
      await t.tap(find.text('Kód másolása'));
      await t.pumpAndSettle();
      expect(copied, [url, token]);
      expect(r.invites, 1);
      expect(
        r.calls,
        2,
      ); // Existing pending-invite refresh; copying adds no read.
    },
  );
  test('8A missing URL response does not derive fallback URL', () async {
    final auth = TestAuth(), functions = Functions();
    addTearDown(auth.events.close);
    functions.callable.reply = () async => payload()..remove('inviteUrl');
    await expectLater(
      CallableFamilyRepository(auth: auth, functions: functions).createInvite(),
      throwsA(isA<FamilyMutationException>()),
    );
  });
}
