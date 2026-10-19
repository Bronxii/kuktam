import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import '../../../households/production_household_context.dart';
import '../../domain/models/shopping_item.dart';
import '../../domain/shopping_mutation.dart';
import 'shopping_coordinator.dart';
import 'shopping_mutation_dispatcher.dart';
import 'shopping_mutation_transport.dart';
import 'shopping_outbox.dart';

class FirestoreShoppingCoordinatorBackend
    implements ShoppingCoordinatorBackend, ShoppingAbsenceVerifier {
  FirestoreShoppingCoordinatorBackend(
    this.firestore,
    this.auth,
    this.functions,
  );
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  @override
  Future<Set<String>> absentItems(
    String uid,
    String householdId,
    List<String> ids,
  ) async {
    _guard(uid);
    final absent = ids.toSet();
    for (var offset = 0; offset < ids.length; offset += 10) {
      final snapshot = await firestore
          .collection('households/$householdId/shoppingItems')
          .where(
            FieldPath.documentId,
            whereIn: ids.sublist(offset, (offset + 10).clamp(0, ids.length)),
          )
          .get(const GetOptions(source: Source.server));
      _guard(uid);
      absent.removeAll(snapshot.docs.map((d) => d.id));
    }
    return absent;
  }

  void _guard(String uid) {
    if (auth.currentUser?.uid != uid) {
      throw StateError('Shopping session changed');
    }
  }

  @override
  Stream<String> households(String uid) {
    _guard(uid);
    return productionHouseholdContext(auth: auth).watch();
  }

  @override
  Stream<ShoppingMutationContext> contexts(String uid, String householdId) {
    _guard(uid);
    return firestore
        .doc('households/$householdId')
        .snapshots(includeMetadataChanges: true)
        .where(
          (d) =>
              !d.metadata.isFromCache &&
              !d.metadata.hasPendingWrites &&
              d.data()?['shoppingEpoch'] is String,
        )
        .map((d) {
          _guard(uid);
          return ShoppingMutationContext(
            uid: uid,
            householdId: householdId,
            epoch: d.data()!['shoppingEpoch'] as String,
          );
        });
  }

  @override
  Future<ShoppingMutationContext> ensureContext(String uid) async {
    _guard(uid);
    final result = await functions
        .httpsCallable('ensureShoppingContext')
        .call<Map<String, dynamic>>({});
    _guard(uid);
    return ShoppingMutationContext(
      uid: uid,
      householdId: result.data['householdId'] as String,
      epoch: result.data['epoch'] as String,
    );
  }

  @override
  Stream<List<ShoppingItem>> items(String uid, String householdId) {
    _guard(uid);
    return firestore
        .collection('households/$householdId/shoppingItems')
        .orderBy('createdAt')
        .snapshots()
        .map((s) {
          _guard(uid);
          return s.docs.map((d) {
            final v = d.data();
            return ShoppingItem(
              id: d.id,
              name: v['name'] as String,
              quantity: (v['quantity'] as num).toDouble(),
              unit: v['unit'] as String,
              isChecked: v['isChecked'] as bool,
              revision: (v['revision'] as num?)?.toInt() ?? 0,
            );
          }).toList();
        });
  }
}

final _instances = Expando<Future<ShoppingCoordinator>>();
Future<ShoppingCoordinator> productionShoppingCoordinator({
  FirebaseAuth? auth,
}) {
  final current = auth ?? FirebaseAuth.instance;
  return _instances[current] ??= _open(current);
}

Future<ShoppingCoordinator> _open(FirebaseAuth auth) async {
  final box = await ShoppingOutbox.open();
  final firestore = FirebaseFirestore.instance;
  final dispatcher = ShoppingMutationDispatcher(
    outbox: box,
    transport: FirestoreShoppingMutationTransport(
      firestore,
      () => auth.currentUser?.uid,
    ),
    currentUid: () => auth.currentUser?.uid,
  );
  final coordinator = ShoppingCoordinator(
    outbox: box,
    dispatcher: dispatcher,
    backend: FirestoreShoppingCoordinatorBackend(
      firestore,
      auth,
      FirebaseFunctions.instanceFor(region: 'europe-west1'),
    ),
    currentUid: () => auth.currentUser?.uid,
  );
  auth.authStateChanges().map((u) => u?.uid).distinct().listen((uid) {
    unawaited(coordinator.bind(uid).catchError((Object _) {}));
  });
  WidgetsBinding.instance.addObserver(_ShoppingResume(dispatcher));
  return coordinator;
}

class _ShoppingResume with WidgetsBindingObserver {
  _ShoppingResume(this.dispatcher);
  final ShoppingMutationDispatcher dispatcher;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(dispatcher.recoverObservation().catchError((Object _) {}));
    }
  }
}
