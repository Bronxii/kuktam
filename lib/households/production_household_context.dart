import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'cached_household_gateway.dart';
import 'callable_household_gateway.dart';

class SecureHouseholdContextStorage implements HouseholdContextStorage {
  SecureHouseholdContextStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String uid) =>
      'household_v1_${base64Url.encode(utf8.encode(uid))}';
  @override
  Future<String?> read(String uid) => _storage.read(key: _key(uid));
  @override
  Future<void> write(String uid, String value) =>
      _storage.write(key: _key(uid), value: value);
  @override
  Future<void> clear(String uid) => _storage.delete(key: _key(uid));
}

final _contexts = Expando<CachedHouseholdGateway>();
CachedHouseholdGateway productionHouseholdContext({FirebaseAuth? auth}) {
  final current = auth ?? FirebaseAuth.instance;
  return _contexts[current] ??= CachedHouseholdGateway(
    currentUid: () => current.currentUser?.uid,
    sessions: current.authStateChanges().map((u) => u?.uid),
    authoritative: CallableHouseholdGateway(auth: current),
    storage: SecureHouseholdContextStorage(),
    isTransient: (error) =>
        error is FirebaseException &&
        [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(error.code),
    serverChanges: (uid) => FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .where((s) => !s.metadata.isFromCache && !s.metadata.hasPendingWrites)
        .map(
          (s) => s.data()?['shoppingMigrationVersion'] == 1
              ? (s.data()?['activeHouseholdId'] as String?)
              : null,
        ),
  );
}
