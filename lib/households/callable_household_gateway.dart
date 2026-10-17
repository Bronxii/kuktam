import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'household_gateway.dart';

class CallableHouseholdGateway implements HouseholdGateway {
  CallableHouseholdGateway({FirebaseAuth? auth, FirebaseFunctions? functions})
    : _auth = auth ?? FirebaseAuth.instance,
      _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  Future<String> ensure() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Authentication required');
    var changed = false;
    final subscription = _auth.authStateChanges().listen((u) {
      if (u?.uid != uid) changed = true;
    });
    void check() {
      if (changed || _auth.currentUser?.uid != uid) {
        throw StateError('Authenticated session changed');
      }
    }

    try {
      // Bounded client work. A later retry resumes the durable migration.
      for (var attempt = 0; attempt < 20; attempt++) {
        check();
        final result = await _functions
            .httpsCallable('ensurePrivateHousehold')
            .call<Object?>({});
        check();
        final data = result.data;
        if (data is! Map ||
            data['schemaVersion'] != 1 ||
            data['ready'] is! bool) {
          throw StateError('Invalid account initialization response');
        }
        if (data['ready'] == true) {
          final id = data['householdId'];
          if (id is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
            throw StateError('Invalid household identity');
          }
          return id;
        }
      }
      throw StateError('Account initialization pending');
    } finally {
      await subscription.cancel();
    }
  }
}
