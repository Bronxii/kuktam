class FamilyJoinException implements Exception {
  const FamilyJoinException(this.code);
  final String code;
  String get message => switch (code) {
    'INVALID_ARGUMENT' ||
    'NOT_FOUND' => 'A meghívókód érvénytelen. Ellenőrizd a kódot.',
    'EXPIRED' => 'Ez a meghívó lejárt. Kérj új kódot a tulajdonostól.',
    'USED' || 'REVOKED' => 'Ez a meghívó már nem használható.',
    'FAMILY_FULL' => 'A család megtelt. Legfeljebb 8 résztvevő lehet.',
    'ALREADY_MEMBER' || 'ALREADY_IN_FAMILY' =>
      'Már családhoz tartozol. Frissítsd a családi állapotot.',
    'SELF_INVITE' => 'A saját meghívóddal nem csatlakozhatsz.',
    'IN_PROGRESS' ||
    'FAMILY_PREPARING' ||
    'FAMILY_DISSOLVING' => 'Családi művelet van folyamatban. Frissíts később.',
    'ACCOUNT_UNAVAILABLE' || 'ACCOUNT_NOT_READY' =>
      'A fiók jelenlegi állapotában nem lehet csatlakozni.',
    'OWNER_NOT_PRO' ||
    'OWNER_UNAVAILABLE' ||
    'FAMILY_UNAVAILABLE' => 'Ehhez a családhoz most nem lehet csatlakozni.',
    'FEATURE_DISABLED' =>
      'A csatlakozás ebben a környezetben még nem érhető el.',
    _ =>
      'Az eredmény most nem ellenőrizhető. Frissítsd az állapotot; ne kezdj másik csatlakozást.',
  };
}

enum FamilyJoinMode { add, delete }

extension FamilyJoinModeWire on FamilyJoinMode {
  String get wire => this == FamilyJoinMode.add ? 'ADD' : 'DELETE';
}

class FamilyInvitePreview {
  const FamilyInvitePreview(this.ownerEmail, this.expiresAt, this.itemCount);
  final String? ownerEmail;
  final DateTime expiresAt;
  final int itemCount;
  factory FamilyInvitePreview.parse(Object? raw) {
    if (raw is! Map || raw['schemaVersion'] != 1) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    if (raw['eligible'] == false) {
      throw FamilyJoinException(
        raw['code'] is String ? raw['code'] as String : 'UNAVAILABLE',
      );
    }
    final owner = raw['owner'];
    if (raw['code'] != 'VALID' ||
        raw['eligible'] != true ||
        raw['inviteState'] != 'PENDING' ||
        owner is! Map ||
        !(owner['email'] == null || owner['email'] is String) ||
        !_count(raw['privateShoppingItemCount']) ||
        !_time(raw['expiresAt'])) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    return FamilyInvitePreview(
      owner['email'] as String?,
      DateTime.fromMillisecondsSinceEpoch(raw['expiresAt'] as int),
      raw['privateShoppingItemCount'] as int,
    );
  }
}

bool _count(Object? value) =>
    value is int && value >= 0 && value <= 9007199254740991;
bool _time(Object? value) =>
    value is int && value > 0 && value <= 8640000000000000;
final _hash = RegExp(r'^[a-f0-9]{64}$');

class FamilyJoinHandle {
  const FamilyJoinHandle(this.operationId, this.inviteId, this.mode);
  final String operationId, inviteId;
  final FamilyJoinMode mode;
  Map<String, Object?> get request => {
    'operationId': operationId,
    'inviteId': inviteId,
  };
}

class FamilyJoinProgress {
  const FamilyJoinProgress(
    this.handle,
    this.phase,
    this.status,
    this.committed, {
    this.epoch,
    this.hash,
    this.count,
  });
  final FamilyJoinHandle handle;
  final String phase, status;
  final bool committed;
  final String? epoch, hash;
  final int? count;
  bool get terminal => status == 'DONE' || status == 'ABORTED';
  bool get canCancel => status == 'READY' && !committed;
  bool get needsConsent =>
      canCancel &&
      handle.mode == FamilyJoinMode.delete &&
      phase == 'SOURCE_FENCED_WAITING_CONFIRMATION';
  Map<String, Object?> get consent {
    if (!needsConsent || epoch == null || hash == null || count == null) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    return {
      ...handle.request,
      'sourceEpoch': epoch,
      'snapshotHash': hash,
      'sourceItemCount': count,
      'consentVersion': 1,
    };
  }

  factory FamilyJoinProgress.parse(Object? raw, FamilyJoinHandle handle) {
    const phases = [
      'READY_FOR_TRANSFER',
      'SNAPSHOT_SOURCE',
      'SOURCE_FENCED_WAITING_CONFIRMATION',
      'COMMITTED_TRANSFER',
      'CLEAN_SOURCE',
      'TRANSFER_COMPLETE',
      'ACTIVE',
    ];
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['operationId'] != handle.operationId ||
        raw['inviteId'] != handle.inviteId ||
        raw['mode'] != handle.mode.wire ||
        !phases.contains(raw['phase']) ||
        !['READY', 'ABORTED', 'OPERATOR', 'DONE'].contains(raw['status']) ||
        !(raw['committedAt'] == null || _time(raw['committedAt']))) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    final phase = raw['phase'] as String,
        status = raw['status'] as String,
        committed = raw['committedAt'] != null;
    if ([
              'COMMITTED_TRANSFER',
              'CLEAN_SOURCE',
              'TRANSFER_COMPLETE',
              'ACTIVE',
            ].contains(phase) !=
            committed ||
        (status == 'DONE' && phase != 'ACTIVE') ||
        (status == 'ABORTED' && committed)) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    if (phase == 'SOURCE_FENCED_WAITING_CONFIRMATION' &&
        (raw['sourceEpoch'] is! String ||
            (raw['sourceEpoch'] as String).isEmpty ||
            raw['snapshotHash'] is! String ||
            !_hash.hasMatch(raw['snapshotHash'] as String) ||
            !_count(raw['sourceItemCount']) ||
            raw['consentVersion'] != 1)) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    if (!(raw['sourceEpoch'] == null || raw['sourceEpoch'] is String) ||
        !(raw['snapshotHash'] == null || raw['snapshotHash'] is String) ||
        !(raw['sourceItemCount'] == null || _count(raw['sourceItemCount']))) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    return FamilyJoinProgress(
      handle,
      phase,
      status,
      committed,
      epoch: raw['sourceEpoch'] as String?,
      hash: raw['snapshotHash'] as String?,
      count: raw['sourceItemCount'] as int?,
    );
  }
}
