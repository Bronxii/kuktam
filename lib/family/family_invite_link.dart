/// Incoming URI validation only. Membership always requires server preview/JOIN.
String? familyInviteToken(String raw) {
  if (raw.length > 256) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.authority != 'kuktam-67768.web.app' ||
      uri.path != '/family/invite' ||
      uri.hasFragment ||
      !raw.startsWith('https://') ||
      raw != uri.toString()) {
    return null;
  }
  // Current canonical unpadded base64url credential. Reject encoded aliases,
  // duplicate/extra query keys, whitespace, padding and noncanonical pad bits.
  if (!RegExp(
    r'^token=[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$',
  ).hasMatch(uri.query)) {
    return null;
  }
  return uri.queryParameters['token'];
}

/// One active navigation, one recent credential, no persistence or auth queue.
class FamilyLinkRouter {
  FamilyLinkRouter({
    required this.currentUid,
    required this.canNavigate,
    required this.open,
    required this.notice,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String? Function() currentUid;
  final bool Function() canNavigate;
  final Future<void> Function(String token) open;
  final void Function(String message) notice;
  final DateTime Function() _now;
  bool _opening = false;
  String? _lastToken, _lastUid;
  DateTime? _lastAt;

  Future<void> receive(String raw) async {
    final token = familyInviteToken(raw);
    if (token == null) {
      notice('Ez nem érvényes Kuktám családi meghívólink.');
      return;
    }
    final uid = currentUid();
    if (uid == null) {
      _lastToken = null;
      _lastUid = null;
      notice('Jelentkezz be, majd nyisd meg újra a meghívólinket.');
      return;
    }
    final now = _now();
    if (_lastToken == token &&
        _lastUid == uid &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 5)) {
      return;
    }
    if (_opening || !canNavigate()) {
      notice(
        'Előbb fejezd be a megnyitott folyamatot, majd nyisd meg újra a meghívólinket.',
      );
      return;
    }
    _opening = true;
    _lastToken = token;
    _lastUid = uid;
    _lastAt = now;
    try {
      await open(token);
    } finally {
      _opening = false;
    }
  }
}
