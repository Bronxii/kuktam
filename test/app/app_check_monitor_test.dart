import 'dart:async';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/app/app_check_monitor.dart';
import 'package:kuktam/app/firebase_startup.dart';

void main() {
  for (final mode in [AppCheckBuildMode.release, AppCheckBuildMode.profile]) {
    test('$mode always uses Play Integrity, never debug', () {
      expect(
        androidAppCheckProvider(mode),
        isA<AndroidPlayIntegrityProvider>(),
      );
      expect(androidAppCheckProvider(mode), isNot(isA<AndroidDebugProvider>()));
    });
  }
  test('debug selects SDK debug provider without embedded token', () {
    expect(
      androidAppCheckProvider(AppCheckBuildMode.debug),
      isA<AndroidDebugProvider>(),
    );
  });
  test(
    'Firebase completes before App Check, then session composition',
    () async {
      final order = <String>[];
      final firebase = Completer<void>(), activation = Completer<void>();
      final started = startFirebaseApp(
        initializeFirebase: () async {
          order.add('firebase');
          await firebase.future;
        },
        initializeAppCheck: () => activateAppCheckMonitor(
          activate: () async {
            order.add('activate');
            await activation.future;
          },
          requestToken: () async {
            order.add('token');
            return 'synthetic-private-token';
          },
          diagnostic: (_) => fail('unexpected diagnostic'),
        ),
        composeApp: () async => order.add('auth/firestore/monetization'),
      );
      expect(order, ['firebase']);
      firebase.complete();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['firebase', 'activate']);
      activation.complete();
      await started;
      expect(order, [
        'firebase',
        'activate',
        'token',
        'auth/firestore/monetization',
      ]);
    },
  );
  for (final stage in ['activation', 'token']) {
    test('$stage error is sanitized and does not block startup', () async {
      final logs = <String>[];
      var composed = false, tokenCalls = 0;
      await startFirebaseApp(
        initializeFirebase: () async {},
        initializeAppCheck: () => activateAppCheckMonitor(
          activate: () async {
            if (stage == 'activation') throw StateError('SENSITIVE-token');
          },
          requestToken: () async {
            tokenCalls++;
            throw StateError('SENSITIVE-token');
          },
          diagnostic: logs.add,
        ),
        composeApp: () async {
          composed = true;
        },
      );
      expect(composed, isTrue);
      expect(tokenCalls, stage == 'activation' ? 0 : 1);
      expect(logs, [
        stage == 'activation'
            ? 'App Check monitor: activation unavailable; startup continues.'
            : 'App Check monitor: token unavailable; startup continues.',
      ]);
      expect(logs.join(), isNot(contains('SENSITIVE')));
    });
  }
  for (final token in <String?>[null, '', 'synthetic-private-token']) {
    test(
      'token result never logged: ${token == null
          ? "null"
          : token.isEmpty
          ? "empty"
          : "present"}',
      () async {
        final logs = <String>[];
        await activateAppCheckMonitor(
          activate: () async {},
          requestToken: () async => token,
          diagnostic: logs.add,
        );
        expect(logs.length, token == null || token.isEmpty ? 1 : 0);
        expect(logs.join(), isNot(contains('synthetic-private-token')));
      },
    );
  }
  for (final stage in ['activation', 'token']) {
    testWidgets('hung $stage times out without blocking composition', (
      tester,
    ) async {
      var composed = false;
      final pending = Completer<void>();
      final task = startFirebaseApp(
        initializeFirebase: () async {},
        initializeAppCheck: () => activateAppCheckMonitor(
          activate: () async {
            if (stage == 'activation') await pending.future;
          },
          requestToken: () async {
            await pending.future;
            return null;
          },
          diagnostic: (_) {},
        ),
        composeApp: () async {
          composed = true;
        },
      );
      await tester.pump();
      expect(composed, isFalse);
      await tester.pump(const Duration(seconds: 6));
      await task;
      expect(composed, isTrue);
      pending.complete();
      await tester.pump();
    });
  }
  test('unrelated Firebase failure is not swallowed', () async {
    var activated = false, composed = false;
    await expectLater(
      startFirebaseApp(
        initializeFirebase: () async => throw StateError('firebase failed'),
        initializeAppCheck: () async {
          activated = true;
        },
        composeApp: () async {
          composed = true;
        },
      ),
      throwsStateError,
    );
    expect(activated, isFalse);
    expect(composed, isFalse);
  });
  test('unrelated composition failure is not swallowed', () async {
    await expectLater(
      startFirebaseApp(
        initializeFirebase: () async {},
        initializeAppCheck: () async {},
        composeApp: () async => throw StateError('composition failed'),
      ),
      throwsStateError,
    );
  });
}
