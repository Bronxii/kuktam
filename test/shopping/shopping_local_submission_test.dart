import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/data/repositories/shopping_local_submission.dart';

void main() {
  test(
    'local pending acceptance completes before remote ack; commit exactly once',
    () async {
      final events = StreamController<bool>();
      final ack = Completer<void>();
      var calls = 0, errors = 0;
      final saved = submitShoppingLocally(
        commit: () {
          calls++;
          return ack.future;
        },
        localAcceptance: events.stream,
        isCurrent: () => true,
        onSyncFailure: () => errors++,
      );
      events.add(true);
      await saved;
      expect(ack.isCompleted, false);
      expect(calls, 1);
      ack.complete();
      await Future<void>.value();
      expect(errors, 0);
      await events.close();
    },
  );
  test('nonmatching cached event does not claim acceptance', () async {
    final events = StreamController<bool>();
    final ack = Completer<void>();
    var done = false;
    final saved = submitShoppingLocally(
      commit: () => ack.future,
      localAcceptance: events.stream,
      isCurrent: () => true,
      onSyncFailure: () {},
    ).then((_) => done = true);
    events.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(done, false);
    ack.complete();
    await saved;
    await events.close();
  });
  for (final synchronous in [true, false]) {
    test(
      'immediate commit error propagates synchronous=$synchronous',
      () async {
        await expectLater(
          submitShoppingLocally(
            commit: () {
              if (synchronous) throw StateError('local');
              return Future<void>.error(StateError('local'));
            },
            localAcceptance: const Stream.empty(),
            isCurrent: () => true,
            onSyncFailure: () => fail('not a late error'),
          ),
          throwsStateError,
        );
      },
    );
  }
  test('late rejection reported once without retry', () async {
    final ack = Completer<void>();
    var errors = 0;
    await submitShoppingLocally(
      commit: () => ack.future,
      localAcceptance: Stream.value(true),
      isCurrent: () => true,
      onSyncFailure: () => errors++,
    );
    ack.completeError(StateError('denied'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, 1);
  });
  test('account switch suppresses old account late error UI', () async {
    var current = true, errors = 0;
    final ack = Completer<void>();
    await submitShoppingLocally(
      commit: () => ack.future,
      localAcceptance: Stream.value(true),
      isCurrent: () => current,
      onSyncFailure: () => errors++,
    );
    current = false;
    ack.completeError(StateError('denied'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, 0);
  });
  test(
    'session changed before local acceptance rejects submission result',
    () async {
      final ack = Completer<void>();
      await expectLater(
        submitShoppingLocally(
          commit: () => ack.future,
          localAcceptance: Stream.value(true),
          isCurrent: () => false,
          onSyncFailure: () {},
        ),
        throwsStateError,
      );
      ack.complete();
    },
  );
  test(
    'listener error does not retry or mask successful server commit',
    () async {
      var calls = 0;
      await submitShoppingLocally(
        commit: () async {
          calls++;
        },
        localAcceptance: Stream.error(StateError('listener')),
        isCurrent: () => true,
        onSyncFailure: () => fail('unexpected'),
      );
      expect(calls, 1);
    },
  );
}
