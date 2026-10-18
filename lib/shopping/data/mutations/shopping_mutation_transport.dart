import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/shopping_mutation.dart';

class ShoppingReceiptSnapshot {
  const ShoppingReceiptSnapshot({
    required this.fromServer,
    required this.documents,
  });
  final bool fromServer;
  final Map<String, Map<String, dynamic>> documents;
}

abstract interface class ShoppingMutationTransport {
  Stream<ShoppingReceiptSnapshot> observe(String uid, List<String> ids);
  Future<void> create(ShoppingMutationRequest request);
  Future<ShoppingReceiptSnapshot> lookup(String uid, List<String> ids);
}

/// One bounded receipt query; no per-command listeners and no canonical writes.
class FirestoreShoppingMutationTransport implements ShoppingMutationTransport {
  FirestoreShoppingMutationTransport(this.firestore, this.currentUid);
  final FirebaseFirestore firestore;
  final String? Function() currentUid;

  @override
  Future<ShoppingReceiptSnapshot> lookup(String uid, List<String> ids) async {
    if (ids.isEmpty || ids.length > 10 || currentUid() != uid) {
      throw StateError('Invalid mutation lookup');
    }
    final snapshot = await firestore
        .collection('users')
        .doc(uid)
        .collection('shoppingMutations')
        .where(FieldPath.documentId, whereIn: ids)
        .get(const GetOptions(source: Source.server));
    if (currentUid() != uid) throw StateError('Shopping session changed');
    return ShoppingReceiptSnapshot(
      fromServer: true,
      documents: {for (final d in snapshot.docs) d.id: d.data()},
    );
  }

  @override
  Stream<ShoppingReceiptSnapshot> observe(String uid, List<String> ids) {
    if (ids.isEmpty || ids.length > 10 || currentUid() != uid) {
      throw StateError('Invalid mutation observation');
    }
    return firestore
        .collection('users')
        .doc(uid)
        .collection('shoppingMutations')
        .where(FieldPath.documentId, whereIn: List<String>.unmodifiable(ids))
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (currentUid() != uid) throw StateError('Shopping session changed');
          return ShoppingReceiptSnapshot(
            fromServer:
                !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites,
            documents: {for (final d in snapshot.docs) d.id: d.data()},
          );
        });
  }

  @override
  Future<void> create(ShoppingMutationRequest request) {
    if (currentUid() != request.context.uid) {
      throw StateError('Shopping session changed');
    }
    // Creation is attempted only after authoritative absence, never blind replay
    // over a processed immutable receipt. Rules prohibit replacing existing data.
    return firestore
        .collection('users')
        .doc(request.context.uid)
        .collection('shoppingMutations')
        .doc(request.mutationId)
        .set({
          ...request.toJson(),
          'submittedAt': FieldValue.serverTimestamp(),
        });
  }
}
