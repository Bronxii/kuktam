import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/households/household_gateway.dart';
import 'package:kuktam/households/cached_household_gateway.dart';
import 'package:kuktam/households/household_gate.dart';
import 'package:kuktam/households/switch_household_stream.dart';

class MemoryContexts implements HouseholdContextStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String uid) async => values[uid];
  @override
  Future<void> write(String uid, String value) async {
    values[uid] = value;
  }

  @override
  Future<void> clear(String uid) async {
    values.remove(uid);
  }

  void seed(String uid, String id) {
    values[uid] = jsonEncode({'version': 1, 'uid': uid, 'householdId': id});
  }
}

class Authority implements HouseholdGateway {
  int calls = 0;
  Future<String> Function() reply = () async => 'home-a';
  @override
  Future<String> ensure() {
    calls++;
    return reply();
  }
}

class Offline implements Exception {}

class Fixture {
  String? uid = 'a';
  final auth = StreamController<String?>.broadcast(sync: true);
  final remote = StreamController<String?>.broadcast(sync: true);
  final storage = MemoryContexts();
  final authority = Authority();
  late final context = CachedHouseholdGateway(
    currentUid: () => uid,
    sessions: auth.stream,
    authoritative: authority,
    storage: storage,
    isTransient: (e) => e is Offline,
    serverChanges: (_) => remote.stream,
  );
  void switchTo(String? value) {
    uid = value;
    auth.add(value);
  }

  Future<void> close() async {
    await auth.close();
    await remote.close();
  }
}

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'first online use persists only authoritative completed context',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final pending = Completer<String>();
      f.authority.reply = () => pending.future;
      final ready = f.context.ensure();
      await flush();
      expect(f.storage.values, isEmpty);
      pending.complete('confirmed');
      expect(await ready, 'confirmed');
      expect(jsonDecode(f.storage.values['a']!)['householdId'], 'confirmed');
    },
  );
  testWidgets(
    'first offline use requires connectivity; explicit retry provisions',
    (tester) async {
      final f = Fixture();
      addTearDown(f.close);
      f.authority.reply = () async => throw Offline();
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdGate(gateway: f.context, child: const Text('Main')),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsNothing);
      expect(find.textContaining('internetkapcsolat'), findsOneWidget);
      expect(f.storage.values, isEmpty);
      f.authority.reply = () async => 'home-a';
      await tester.tap(find.text('Újrapróbálás'));
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'verified offline user opens app without waiting for a hung network',
    (tester) async {
      final f = Fixture();
      addTearDown(f.close);
      f.storage.seed('a', 'cached');
      final pending = Completer<String>();
      f.authority.reply = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: HouseholdGate(gateway: f.context, child: const Text('Main')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsOneWidget);
      pending.completeError(Offline());
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('new gateway after restart reads persisted context offline', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.context.ensure();
    f.authority.reply = () async => throw Offline();
    final restarted = CachedHouseholdGateway(
      currentUid: () => f.uid,
      sessions: f.auth.stream,
      authoritative: f.authority,
      storage: f.storage,
      isTransient: (e) => e is Offline,
      serverChanges: (_) => f.remote.stream,
    );
    expect(await restarted.ensure(), 'home-a');
    await flush();
    expect(f.storage.values.containsKey('a'), true);
  });
  test('A sign-out B A never reuses another users context', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.context.ensure();
    f.switchTo(null);
    await expectLater(
      f.context.ensure(),
      throwsA(isA<HouseholdSessionChanged>()),
    );
    f.switchTo('b');
    f.authority.reply = () async => throw Offline();
    await expectLater(f.context.ensure(), throwsA(isA<Offline>()));
    expect(f.storage.values.containsKey('b'), false);
    f.switchTo('a');
    expect(await f.context.ensure(), 'home-a');
    await flush();
  });
  test(
    'in-flight account switch including ABA rejects old session result',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      final pending = Completer<String>();
      f.authority.reply = () => pending.future;
      final call = f.context.ensure();
      await flush();
      f.switchTo('b');
      f.switchTo('a');
      pending.complete('old');
      await expectLater(call, throwsA(isA<HouseholdSessionChanged>()));
      expect(f.storage.values, isEmpty);
    },
  );
  for (final corrupt in [
    null,
    'bad',
    '{}',
    jsonEncode({'version': 1, 'uid': 'b', 'householdId': 'wrong'}),
    jsonEncode({'version': 1, 'uid': 'a', 'householdId': 'a/b'}),
  ]) {
    test('invalid or cleared cache requires authority: $corrupt', () async {
      final f = Fixture();
      addTearDown(f.close);
      if (corrupt != null) f.storage.values['a'] = corrupt;
      f.authority.reply = () async => throw Offline();
      await expectLater(f.context.ensure(), throwsA(isA<Offline>()));
      expect(f.authority.calls, 1);
    });
  }
  test('server switch replaces persisted context and emits new ID', () async {
    final f = Fixture();
    addTearDown(f.close);
    await f.context.ensure();
    final values = <String>[];
    final sub = f.context.watch().listen(values.add);
    await flush();
    f.authority.reply = () async => 'shared-confirmed';
    f.remote.add('shared-untrusted-hint');
    await flush();
    expect(values, ['home-a', 'shared-confirmed']);
    expect(
      jsonDecode(f.storage.values['a']!)['householdId'],
      'shared-confirmed',
    );
    await sub.cancel();
  });
  test(
    'reconnect checks authority even when active ID metadata is unchanged',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      f.storage.seed('a', 'home-a');
      f.authority.reply = () async => throw Offline();
      final values = <String>[], errors = <Object>[];
      final sub = f.context.watch().listen(values.add, onError: errors.add);
      await flush();
      f.authority.reply = () async => throw StateError('accountDeleted');
      f.remote.add('home-a');
      await flush();
      expect(errors, isNotEmpty);
      expect(f.storage.values, isEmpty);
      f.authority.reply = () async => throw Offline();
      await expectLater(f.context.ensure(), throwsA(isA<Offline>()));
      await sub.cancel();
    },
  );
  test(
    'watch closes on signout and does not follow replacement account',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await f.context.ensure();
      final values = <String>[], errors = <Object>[];
      final sub = f.context.watch().listen(values.add, onError: errors.add);
      await flush();
      f.switchTo(null);
      f.switchTo('b');
      f.authority.reply = () async => 'home-b';
      await f.context.ensure();
      await flush();
      expect(values, ['home-a']);
      expect(errors, isNotEmpty);
      await sub.cancel();
    },
  );
  test(
    'context switch cancels old shopping listener and late delivery',
    () async {
      final ids = StreamController<String>(),
          a = StreamController<String>(),
          b = StreamController<String>();
      final values = <String>[];
      var canceled = false;
      a.onCancel = () => canceled = true;
      final sub = switchHouseholdStream(
        ids.stream,
        (id) => id == 'a' ? a.stream : b.stream,
      ).listen(values.add);
      ids.add('a');
      await flush();
      a.add('a item');
      await flush();
      ids.add('b');
      await flush();
      a.add('late a');
      b.add('b item');
      await flush();
      expect(canceled, true);
      expect(values, ['a item', 'b item']);
      await sub.cancel();
      await ids.close();
      await a.close();
      await b.close();
    },
  );
  test(
    'invalidation cancels active shopping listener before further delivery',
    () async {
      final ids = StreamController<String>(),
          items = StreamController<String>();
      final values = <String>[], errors = <Object>[];
      final sub = switchHouseholdStream(
        ids.stream,
        (_) => items.stream,
      ).listen(values.add, onError: errors.add);
      ids.add('a');
      await flush();
      ids.addError(StateError('revoked'));
      await flush();
      items.add('late');
      await flush();
      expect(values, isEmpty);
      expect(errors, hasLength(1));
      await sub.cancel();
      await ids.close();
      await items.close();
    },
  );
}
