import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kuktam/shopping/data/mutations/shopping_coordinator.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_dispatcher.dart';
import 'package:kuktam/shopping/data/mutations/shopping_mutation_transport.dart';
import 'package:kuktam/shopping/data/mutations/shopping_outbox.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_mutation.dart';
import '../recipes/recipe_repository_test.dart'
    show RecipeTestAuth, RecipeTestUser;
import 'shopping_mutation_contract_test.dart' show testContext;

class ClientBackend implements ShoppingCoordinatorBackend {
  List<ShoppingItem> canonical = [];
  final updates = StreamController<List<ShoppingItem>>.broadcast(sync: true);
  int activeListeners = 0, maxListeners = 0;
  bool offline = false;
  @override
  Stream<String> households(String uid) => Stream.value('home-$uid');
  @override
  Stream<ShoppingMutationContext> contexts(String uid, String hid) =>
      offline ? const Stream.empty() : Stream.value(testContext(uid, hid));
  @override
  Future<ShoppingMutationContext> ensureContext(String uid) async {
    if (offline) throw StateError('offline');
    return testContext(uid, 'home-$uid');
  }

  @override
  Stream<List<ShoppingItem>> items(String uid, String hid) =>
      Stream.multi((sink) {
        activeListeners++;
        if (activeListeners > maxListeners) maxListeners = activeListeners;
        final sub = updates.stream.listen(sink.add);
        sink.add(List.of(canonical));
        sink.onCancel = () async {
          activeListeners--;
          await sub.cancel();
        };
      });
  void publish(List<ShoppingItem> value) {
    canonical = value;
    updates.add(value);
  }
}

class ClientTransport implements ShoppingMutationTransport {
  final events = StreamController<ShoppingReceiptSnapshot>.broadcast(
    sync: true,
  );
  final sent = <ShoppingMutationRequest>[];
  @override
  Stream<ShoppingReceiptSnapshot> observe(String uid, List<String> ids) =>
      events.stream;
  @override
  Future<void> create(ShoppingMutationRequest request) async {
    sent.add(request);
  }

  @override
  Future<ShoppingReceiptSnapshot> lookup(String uid, List<String> ids) async =>
      const ShoppingReceiptSnapshot(fromServer: true, documents: {});
}

class ClientFixture {
  late Directory directory;
  late ShoppingOutbox box;
  late ShoppingCoordinator client;
  late ShoppingMutationDispatcher dispatcher;
  final auth = RecipeTestAuth();
  final backend = ClientBackend();
  final transport = ClientTransport();
  late ShoppingRepository repository;
  Future<void> open() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('shopping-client-');
    box = await ShoppingOutbox.open(
      factory: databaseFactoryFfiNoIsolate,
      path: '${directory.path}/journal.db',
    );
    await start();
  }

  Future<void> start() async {
    dispatcher = ShoppingMutationDispatcher(
      outbox: box,
      transport: transport,
      currentUid: () => auth.currentUser?.uid,
    );
    client = ShoppingCoordinator(
      outbox: box,
      dispatcher: dispatcher,
      backend: backend,
      currentUid: () => auth.currentUser?.uid,
    );
    repository = ShoppingRepository(
      firebaseAuth: auth,
      coordinator: Future.value(client),
    );
    await bind('A');
  }

  Future<void> bind(String? uid) async {
    auth.currentUser = uid == null ? null : RecipeTestUser(uid);
    final ready = uid == null
        ? Future<void>.value()
        : client.changes.firstWhere((_) => client.context?.uid == uid);
    await client.bind(uid);
    await ready;
    await client.settled;
  }

  Future<void> restart() async {
    await client.close();
    await box.close();
    box = await ShoppingOutbox.open(
      factory: databaseFactoryFfiNoIsolate,
      path: '${directory.path}/journal.db',
    );
    await start();
  }

  Future<void> canonical(List<ShoppingItem> items) async {
    final next = client.changes.first;
    backend.publish(items);
    await next;
    await client.settled;
  }

  Future<void> receipt(
    ShoppingMutationRequest r,
    String status, {
    String itemId = 'server-id',
    int revision = 1,
    bool? created,
  }) async {
    transport.events.add(
      ShoppingReceiptSnapshot(
        fromServer: true,
        documents: {
          r.mutationId: {
            ...r.toJson(),
            'requestHash': r.requestHash,
            'status': status,
            'results': [
              {
                'code': status,
                'itemId': itemId,
                'revision': revision,
                'created': ?created,
              },
            ],
          }..remove('payloadJson'),
        },
      ),
    );
    await dispatcher.settled;
    final next = client.changes.first;
    backend.publish(List.of(backend.canonical));
    await next;
    await client.settled;
  }

  Future<void> close() async {
    await client.close();
    await box.close();
    await backend.updates.close();
    await transport.events.close();
    await auth.changes.close();
    await directory.delete(recursive: true);
  }
}

ShoppingItem canonicalItem({
  String id = 'tea',
  double quantity = 5,
  int revision = 1,
  bool checked = false,
}) => ShoppingItem(
  id: id,
  name: 'tea',
  quantity: quantity,
  unit: 'db',
  isChecked: checked,
  revision: revision,
);
