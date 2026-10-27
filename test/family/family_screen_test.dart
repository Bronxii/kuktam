import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/family/family_repository.dart';
import 'package:kuktam/family/family_state.dart';
import 'package:kuktam/family/family_screen.dart';
import 'package:kuktam/settings/settings_screen.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'fakes.dart';
import 'family_test.dart' show response;

class Repo implements FamilyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError("Unexpected mutation");
  int calls = 0;
  final events = StreamController<void>.broadcast(sync: true);
  Future<FamilyState> Function() reply = () async => FamilyState.fromResponse({
    'schemaVersion': 1,
    'familyActive': false,
  }, 'a');
  @override
  Stream<void> get sessionChanges => events.stream;
  @override
  Future<FamilyState> load() {
    calls++;
    return reply();
  }
}

class ProfileAuth implements AuthRepository {
  @override
  User? currentUser = TestUser('a');
  @override
  bool get isEmailPasswordUser => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected');
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Kuktám',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  Future<void> show(WidgetTester t, Repo repo) async {
    addTearDown(repo.events.close);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: FamilyScreen(repository: repo),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('7A Profile authenticated entry opens Family and returns', (
    t,
  ) async {
    final repo = Repo();
    addTearDown(repo.events.close);
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authRepository: ProfileAuth(),
          familyRepository: repo,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Családi megosztás'), findsOneWidget);
    expect(repo.calls, 0);
    await t.tap(find.text('Családi megosztás'));
    await t.pumpAndSettle();
    expect(find.byType(FamilyScreen), findsOneWidget);
    expect(repo.calls, 1);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(repo.events.hasListener, false);
  });
  testWidgets('7A Profile anonymous has no Family entry', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SettingsScreen(authRepository: ProfileAuth()..currentUser = null),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Családi megosztás'), findsNothing);
  });
  testWidgets('7A private historical-only state has no mutation controls', (
    t,
  ) async {
    final repo = Repo();
    await show(t, repo);
    expect(find.text('Még nem vagy család tagja'), findsOneWidget);
    expect(find.text('Aktív család'), findsNothing);
    for (final action in [
      'Meghívás',
      'Kilépés',
      'Eltávolítás',
      'Család létrehozása',
      'Feloldás',
    ]) {
      expect(find.text(action), findsNothing);
    }
    await t.pump();
    expect(repo.calls, 1);
  });
  for (final owner in [true, false]) {
    testWidgets('7A ${owner ? 'owner' : 'member'} summary and owner identity', (
      t,
    ) async {
      final repo = Repo()
        ..reply = () async => FamilyState.fromResponse(
          response(role: owner ? 'owner' : 'member'),
          owner ? 'a' : 'm1',
        );
      await show(t, repo);
      expect(find.text('Aktív család'), findsOneWidget);
      expect(find.text('owner@example.test'), findsOneWidget);
      expect(
        find.text(owner ? 'Tulajdonos · Te' : 'Tulajdonos'),
        findsOneWidget,
      );
      expect(
        find.text(
          owner ? 'Tulajdonos vagy · 2 résztvevő' : 'Tag vagy · 2 résztvevő',
        ),
        findsOneWidget,
      );
      expect(find.text('Ismeretlen tag'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  }
  testWidgets('7A eight participants remain bounded and scrollable', (t) async {
    final repo = Repo()
      ..reply = () async => FamilyState.fromResponse(response(count: 8), 'a');
    await show(t, repo);
    expect(find.byType(ListTile), findsNWidgets(8));
    expect(t.takeException(), isNull);
    await t.drag(find.byType(ListView), const Offset(0, -500));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('7A loading never flashes private-only', (t) async {
    final pending = Completer<FamilyState>(), repo = Repo();
    addTearDown(repo.events.close);
    repo.reply = () => pending.future;
    await t.pumpWidget(MaterialApp(home: FamilyScreen(repository: repo)));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Még nem vagy család tagja'), findsNothing);
    pending.complete(FamilyState.fromResponse(response(), 'a'));
    await t.pumpAndSettle();
    expect(find.text('Aktív család'), findsOneWidget);
  });
  testWidgets('7A error hides raw detail and retry performs one fresh read', (
    t,
  ) async {
    final repo = Repo()
      ..reply = () async => throw StateError('PRIVATE-DETAILS');
    await show(t, repo);
    expect(find.textContaining('PRIVATE-DETAILS'), findsNothing);
    expect(find.text('Újrapróbálás'), findsOneWidget);
    repo.reply = () async => FamilyState.fromResponse(response(), 'a');
    await t.tap(find.text('Újrapróbálás'));
    await t.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.text('Aktív család'), findsOneWidget);
  });
  testWidgets('7A in-progress has no participants or mutation actions', (
    t,
  ) async {
    final repo = Repo()..reply = () async => FamilyState.inProgress('a');
    await show(t, repo);
    expect(find.text('Folyamatban lévő családi művelet'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
  testWidgets('7A session change clears identities and ignores late response', (
    t,
  ) async {
    final repo = Repo();
    await show(t, repo);
    final pending = Completer<FamilyState>();
    repo.reply = () => pending.future;
    await t.tap(find.byTooltip('Frissítés'));
    await t.pump();
    repo.events.add(null);
    await t.pump();
    pending.complete(FamilyState.fromResponse(response(), 'a'));
    await t.pumpAndSettle();
    expect(find.text('owner@example.test'), findsNothing);
    expect(find.textContaining('bejelentkezés megváltozott'), findsOneWidget);
  });
}
