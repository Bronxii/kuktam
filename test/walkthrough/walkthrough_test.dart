import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/app/app.dart';
import 'package:kuktam/features/walkthrough/data/walkthrough_store.dart';
import 'package:kuktam/features/walkthrough/presentation/walkthrough_gate.dart';
import 'package:kuktam/features/walkthrough/presentation/walkthrough_screen.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/features/auth/presentation/widgets/account_deletion_dialog.dart';
import '../auth/email_verification_test.dart' as email;
import '../auth/account_deletion_test.dart' as deletion;
import 'walkthrough_store_test.dart' show Preferences;

class MemoryStore implements WalkthroughStore {
  bool? completed;
  bool failRead = false, failWrite = false;
  int reads = 0, writes = 0;
  Completer<void>? pending;
  @override
  Future<bool> isCompleted() async {
    reads++;
    if (failRead) throw StateError('read');
    return completed ?? false;
  }

  @override
  Future<void> complete() async {
    writes++;
    if (pending != null) await pending!.future;
    if (failWrite) throw StateError('write');
    completed = true;
  }
}

const titles = [
  'Tartsd egy helyen a saját receptjeidet.',
  'A szükséges hozzávalók mindig kéznél vannak.',
  'Másold be, a Kuktám pedig segít feldolgozni.',
  'Igazítsd a receptet ahhoz, amennyire szükséged van.',
  'Találd meg, mit tudsz elkészíteni abból, ami otthon van.',
];
void main() {
  for (final skip in [true, false]) {
    testWidgets(
      'KuktamApp ${skip ? "skip" : "finish"} reaches AuthGate and restart retains preference',
      (tester) async {
        final disk = <String, Object>{};
        final auth = email.TestAuth(email.TestUser(true, ['password']));
        Widget root() => KuktamApp(
          authRepository: AuthRepository(firebaseAuth: auth),
          walkthroughStore: SharedPreferencesWalkthroughStore(
            preferences: Preferences(disk),
          ),
        );
        await tester.pumpWidget(root());
        await tester.pumpAndSettle();
        expect(find.byType(AuthGate), findsNothing);
        if (!skip) {
          for (var i = 0; i < 4; i++) {
            await tester.tap(find.text('Következő'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.text(skip ? 'Kihagyás' : 'Kezdjük'));
        await tester.pump();
        auth.changes.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
        expect(disk, {'walkthroughCompleted': true});
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(root());
        await tester.pump();
        auth.changes.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(WalkthroughScreen), findsNothing);
        expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await auth.changes.close();
      },
    );
  }
  Widget app(
    MemoryStore store, {
    Widget child = const Scaffold(body: Text('Auth destination')),
    double scale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: WalkthroughGate(store: store, child: child),
  );
  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Következő'));
    await tester.pumpAndSettle();
  }

  for (final initial in [null, false, true]) {
    testWidgets('completed=$initial startup', (tester) async {
      final store = MemoryStore()..completed = initial;
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(
        find.byType(WalkthroughScreen),
        initial == true ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Auth destination'),
        initial == true ? findsOneWidget : findsNothing,
      );
      expect(store.reads, 1);
      expect(store.writes, 0);
    });
  }
  testWidgets(
    'five exact titles in order; neutral content; finish persists before transition',
    (tester) async {
      final store = MemoryStore()..pending = Completer<void>();
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        expect(find.text(titles[i]).hitTestable(), findsOneWidget);
        expect(find.text('${i + 1} / 5'), findsOneWidget);
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(
            RegExp(
              r'\b(Free|Pro|upgrade|subscription)\b',
              caseSensitive: false,
            ).hasMatch(text.data ?? ''),
            isFalse,
          );
        }
        expect(find.byIcon(Icons.lock), findsNothing);
        if (i < 4) await next(tester);
      }
      final finish = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kezdjük'))
          .onPressed!;
      finish();
      finish();
      await tester.pump();
      expect(store.writes, 1);
      expect(find.text('Auth destination'), findsNothing);
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(store.completed, isTrue);
      expect(find.text('Auth destination'), findsOneWidget);
    },
  );
  testWidgets('skip, rebuild and restart retain device completion', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    final skip = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Kihagyás'))
        .onPressed!;
    skip();
    skip();
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    expect(store.reads, 2);
    expect(find.byType(WalkthroughScreen), findsNothing);
  });
  testWidgets('swipe/button/back and first-page system Back cannot bypass', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 5'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('4 / 5'), findsOneWidget);
    await tester.tap(find.text('Vissza'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
    expect(store.writes, 0);
  });
  testWidgets(
    'read failure shows walkthrough; write failure preserves page and supports retry',
    (tester) async {
      final store = MemoryStore()
        ..failRead = true
        ..failWrite = true;
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);
      await tester.tap(find.text('Kihagyás'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nem sikerült elmenteni'), findsOneWidget);
      expect(find.text('Auth destination'), findsNothing);
      store.failWrite = false;
      await tester.tap(find.text('Kihagyás'));
      await tester.pumpAndSettle();
      expect(store.completed, isTrue);
      expect(find.text('Auth destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(412, 915),
    const Size(800, 360),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all pages and CTA at $size scale=$scale without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryStore();
        await tester.pumpWidget(app(store, scale: scale));
        await tester.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          expect(
            find.text(i == 4 ? 'Kezdjük' : 'Következő').hitTestable(),
            findsOneWidget,
          );
          await tester.drag(find.byType(PageView), const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (i < 4) await next(tester);
        }
      });
    }
  }
  testWidgets(
    'completed wrapper survives logout and account switch; actual AuthGate used',
    (tester) async {
      final store = MemoryStore();
      final auth = email.TestAuth(email.TestUser(true, ['password']));
      final gate = AuthGate(
        authRepository: AuthRepository(firebaseAuth: auth),
        mainBuilder: (_) => const Scaffold(body: Text('Main destination')),
      );
      await tester.pumpWidget(app(store, child: gate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kihagyás'));
      await tester.pump();
      auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      auth.user = auth.loginUser;
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(find.text('Main destination'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
      auth.user = email.TestUser(false, ['google.com']);
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(find.text('Main destination'), findsOneWidget);
      expect(store.writes, 1);
      expect(store.completed, isTrue);
      expect(find.byType(WalkthroughScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );
  testWidgets('actual account deletion does not reset completed walkthrough', (
    tester,
  ) async {
    final store = MemoryStore()..completed = true;
    final f = deletion.Fixture();
    final gate = AuthGate(
      authRepository: AuthRepository(
        firebaseAuth: f.auth,
        googleSignIn: f.google,
      ),
      mainBuilder: (context) => Scaffold(
        body: TextButton(
          child: const Text('Delete'),
          onPressed: () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AccountDeletionDialog(repository: f.repo),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(store, child: gate));
    await tester.pump();
    f.auth.events.add(f.user);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Fiók törlése'));
    await tester.pumpAndSettle();
    expect(f.user.deletes, 1);
    expect(find.text('Bejelentkezés e-maillel'), findsOneWidget);
    expect(store.completed, isTrue);
    expect(store.writes, 0);
    expect(store.reads, 1);
  });
}
