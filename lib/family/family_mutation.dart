enum FamilyMutationFailure {
  proRequired,
  alreadyFamily,
  inProgress,
  accountUnavailable,
  capacity,
  pendingLimit,
  notOwner,
  unavailable,
  signedOut,
}

class FamilyMutationException implements Exception {
  const FamilyMutationException(this.reason);
  final FamilyMutationFailure reason;
  String get message => switch (reason) {
    FamilyMutationFailure.proRequired =>
      'A család tulajdonosának Kuktám Pro szükséges.',
    FamilyMutationFailure.alreadyFamily =>
      'Már családhoz tartozol. Frissítsd a családi állapotot.',
    FamilyMutationFailure.inProgress =>
      'Családi művelet van folyamatban. Frissíts később.',
    FamilyMutationFailure.accountUnavailable =>
      'A fiók jelenlegi állapotában ez a művelet nem érhető el.',
    FamilyMutationFailure.capacity =>
      'A család megtelt. Legfeljebb 8 résztvevő lehet.',
    FamilyMutationFailure.pendingLimit =>
      'Már túl sok érvényes meghívó van. Próbáld újra később.',
    FamilyMutationFailure.notOwner =>
      'Csak a család tulajdonosa hívhat meg tagot.',
    FamilyMutationFailure.signedOut =>
      'A bejelentkezés megváltozott. Nyisd meg újra ezt az oldalt.',
    FamilyMutationFailure.unavailable =>
      'Nem sikerült megerősíteni a művelet eredményét. Frissítsd az állapotot. Új meghívás új kódot hozhat létre.',
  };
}

enum FamilyCreation { complete, inProgress }

class FamilyExitException implements Exception {
  const FamilyExitException(this.code);
  final String code;
  String get message => switch (code) {
    'STALE_MEMBERSHIP' =>
      'A tagság időközben megváltozott. Ellenőrizd a friss családi állapotot.',
    'NOT_ACTIVE_MEMBER' =>
      'Ez a tagság már nem aktív. A családi állapot frissült.',
    'OWNER_CANNOT_LEAVE' || 'OWNER_CANNOT_REMOVE_SELF' =>
      'A tulajdonos ezzel a művelettel nem léphet ki a családból.',
    'NOT_OWNER' ||
    'WRONG_FAMILY' => 'Ezt a tagot csak a család tulajdonosa távolíthatja el.',
    'IN_PROGRESS' => 'Családi művelet van folyamatban. Frissíts később.',
    'ACCOUNT_UNAVAILABLE' =>
      'A fiók jelenlegi állapotában ez a művelet nem érhető el.',
    'FEATURE_DISABLED' =>
      'Ez a művelet ebben a környezetben még nem érhető el.',
    'INTEGRITY_REQUIRES_OPERATOR' =>
      'A tagság most nem ellenőrizhető biztonságosan. Próbáld újra később.',
    _ =>
      'Nem sikerült megerősíteni a művelet eredményét. Ellenőrizd a friss családi állapotot, mielőtt újra próbálod.',
  };
}

/// Transient bearer credential from the existing API, never persisted/logged.
class FamilyInviteResult {
  const FamilyInviteResult({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
  factory FamilyInviteResult.fromResponse(Object? raw) {
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['inviteId'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['inviteId'] as String) ||
        raw['token'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$',
        ).hasMatch(raw['token'] as String) ||
        raw['expiresAt'] is! int ||
        (raw['expiresAt'] as int) <= 0 ||
        (raw['expiresAt'] as int) > 8640000000000000) {
      throw const FamilyMutationException(FamilyMutationFailure.unavailable);
    }
    return FamilyInviteResult(
      code: raw['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(raw['expiresAt'] as int),
    );
  }
}
