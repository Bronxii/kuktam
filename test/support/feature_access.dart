import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:kuktam/pro/feature_gate.dart';
import 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
import 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';
export 'package:kuktam/entitlements/domain/models/entitlement_snapshot.dart';
export 'package:kuktam/entitlements/domain/repositories/entitlement_repository.dart';

ClientEntitlementState accessState(
  ClientEntitlementStatus status, {
  String? uid = 'test-user',
  EntitlementFailure? failure,
}) => ClientEntitlementState(
  status,
  uid: uid,
  failure: failure,
  snapshot: switch (status) {
    ClientEntitlementStatus.free => const EntitlementSnapshot.free(),
    ClientEntitlementStatus.proOnline ||
    ClientEntitlementStatus.proOfflineGrace => const EntitlementSnapshot.pro(),
    ClientEntitlementStatus.checking => const EntitlementSnapshot.checking(),
    _ => const EntitlementSnapshot.unknown(),
  },
);

class AccessRepository implements EntitlementRepository {
  AccessRepository([
    ClientEntitlementStatus status = ClientEntitlementStatus.proOnline,
  ]) : current = accessState(status);
  @override
  ClientEntitlementState current;
  final _events = StreamController<ClientEntitlementState>.broadcast(
    sync: true,
  );
  void set(
    ClientEntitlementStatus status, {
    String? uid = 'test-user',
    EntitlementFailure? failure,
  }) {
    current = accessState(status, uid: uid, failure: failure);
    _events.add(current);
  }

  @override
  Stream<ClientEntitlementState> get changes => _events.stream;
  @override
  Future<void> initializeForUser(
    String uid, {
    bool refreshOnline = true,
  }) async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> reevaluate() async {}
  @override
  Future<void> clearForLogout() async {
    set(ClientEntitlementStatus.unknown, uid: null);
  }

  @override
  Future<void> dispose() async {
    unawaited(_events.close());
  }
}

Widget withProAccess(Widget child) =>
    FeatureAccessScope(repository: AccessRepository(), child: child);
Widget withFreeAccess(Widget child) => FeatureAccessScope(
  repository: AccessRepository(ClientEntitlementStatus.free),
  child: child,
);
