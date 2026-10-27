enum FamilyStatus { privateOnly, activeOwner, activeMember, inProgress }

enum FamilyRole { owner, member }

enum FamilyFailure { unavailable, network, invalidState, signedOut }

class FamilyReadException implements Exception {
  const FamilyReadException(this.reason);
  final FamilyFailure reason;
}

class FamilyParticipant {
  const FamilyParticipant({required this.uid, required this.role, this.email});
  final String uid;
  final FamilyRole role;
  final String? email;
  String get label => email ?? 'Ismeretlen tag';
}

/// Read model only. No Firestore objects, mutation methods or platform APIs.
class FamilyState {
  const FamilyState._(this.status, this.participants, this.currentUid);
  factory FamilyState.inProgress(String uid) =>
      FamilyState._(FamilyStatus.inProgress, const [], uid);
  final FamilyStatus status;
  final List<FamilyParticipant> participants;
  final String currentUid;
  FamilyParticipant? get owner => participants.isEmpty
      ? null
      : participants.firstWhere((p) => p.role == FamilyRole.owner);

  factory FamilyState.fromResponse(Object? value, String uid) {
    Never invalid() =>
        throw const FamilyReadException(FamilyFailure.invalidState);
    if (uid.isEmpty ||
        value is! Map ||
        value['schemaVersion'] != 1 ||
        value['familyActive'] is! bool) {
      invalid();
    }
    if (value['familyActive'] == false) {
      if (value.containsKey('members') || value.containsKey('role')) invalid();
      return FamilyState._(FamilyStatus.privateOnly, const [], uid);
    }
    final role = value['role'];
    final rows = value['members'];
    if (!['owner', 'member'].contains(role) ||
        rows is! List ||
        rows.isEmpty ||
        rows.length > 8) {
      invalid();
    }
    final members = <FamilyParticipant>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map) invalid();
      final id = row['memberId'], r = row['role'], email = row['email'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 128 ||
          id.contains('/') ||
          !ids.add(id) ||
          !['owner', 'member'].contains(r) ||
          !(email == null || email is String && email.length <= 320)) {
        invalid();
      }
      members.add(
        FamilyParticipant(
          uid: id,
          role: r == 'owner' ? FamilyRole.owner : FamilyRole.member,
          email: email is String && email.trim().isNotEmpty
              ? email.trim()
              : null,
        ),
      );
    }
    if (members.where((m) => m.role == FamilyRole.owner).length != 1 ||
        !ids.contains(uid) ||
        (members.firstWhere((m) => m.uid == uid).role == FamilyRole.owner) !=
            (role == 'owner')) {
      invalid();
    }
    members.sort(
      (a, b) => a.role != b.role
          ? (a.role == FamilyRole.owner ? -1 : 1)
          : a.uid.compareTo(b.uid),
    );
    return FamilyState._(
      role == 'owner' ? FamilyStatus.activeOwner : FamilyStatus.activeMember,
      List.unmodifiable(members),
      uid,
    );
  }
}
